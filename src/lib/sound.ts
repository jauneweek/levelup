/**
 * Sound design du Système.
 *
 * Web Audio à la main, aucune librairie (bundle PWA — cf. CLAUDE.md). Trois
 * raisons de préférer Web Audio à `new Audio()` :
 *  - latence quasi nulle (buffers déjà décodés en mémoire) ; un <audio> met
 *    plusieurs dizaines de ms à démarrer, ce qui casse le lien geste → son ;
 *  - deux sons peuvent se superposer (un check pendant un level-up) ;
 *  - un gain par son, donc un tap discret et un boss qui claque.
 *
 * iOS : l'AudioContext naît « suspended » et ne peut être réveillé QUE dans un
 * geste utilisateur. On le déverrouille au tout premier pointerdown, une fois.
 */

const FILES = {
  "tap-1": "/sounds/tap-1.mp3",
  "tap-2": "/sounds/tap-2.mp3",
  "tap-3": "/sounds/tap-3.mp3",
  "check-1": "/sounds/check-1.mp3",
  "check-2": "/sounds/check-2.mp3",
  "check-3": "/sounds/check-3.mp3",
  open: "/sounds/open.mp3",
  close: "/sounds/close.mp3",
  error: "/sounds/error.mp3",
  "levelup-1": "/sounds/levelup-1.mp3",
  "levelup-2": "/sounds/levelup-2.mp3",
  "boss-1": "/sounds/boss-1.mp3",
  "boss-2": "/sounds/boss-2.mp3",
} as const;

type Clip = keyof typeof FILES;

/** Un tap doit s'entendre sans jamais fatiguer ; un boss doit dominer. */
const GAIN: Record<Clip, number> = {
  "tap-1": 0.3,
  "tap-2": 0.3,
  "tap-3": 0.3,
  "check-1": 0.55,
  "check-2": 0.55,
  "check-3": 0.6,
  open: 0.35,
  close: 0.35,
  error: 0.5,
  "levelup-1": 0.7,
  "levelup-2": 0.75,
  "boss-1": 0.7,
  "boss-2": 0.7,
};

/* Chargés dès le déverrouillage : ce sont les sons du geste, ils doivent être
   prêts avant le premier tap. Le reste (level-up, boss) est rare et se charge
   en tâche de fond. */
const EAGER: Clip[] = [
  "tap-1",
  "tap-2",
  "tap-3",
  "check-1",
  "check-2",
  "check-3",
  "open",
  "close",
  "error",
];

const PREF_KEY = "levelup:sound";

let ctx: AudioContext | null = null;
const buffers = new Map<Clip, AudioBuffer>();
const loading = new Map<Clip, Promise<AudioBuffer | null>>();

/**
 * Préférence sonore. localStorage est ICI légitime : c'est un réglage
 * d'appareil (on veut le son coupé sur le téléphone du bureau et pas sur celui
 * du salon), pas de l'état de jeu — lequel reste intégralement serveur.
 */
export function soundEnabled(): boolean {
  if (typeof localStorage === "undefined") return false;
  return localStorage.getItem(PREF_KEY) !== "off";
}

export function setSoundEnabled(on: boolean) {
  if (typeof localStorage === "undefined") return;
  localStorage.setItem(PREF_KEY, on ? "on" : "off");
  if (on) resumeCtx();
}

async function load(clip: Clip): Promise<AudioBuffer | null> {
  const cached = buffers.get(clip);
  if (cached) return cached;

  const inFlight = loading.get(clip);
  if (inFlight) return inFlight;

  const task = (async () => {
    try {
      const audio = ctx;
      if (!audio) return null;
      const res = await fetch(FILES[clip]);
      const bytes = await res.arrayBuffer();
      const buf = await audio.decodeAudioData(bytes);
      buffers.set(clip, buf);
      return buf;
    } catch {
      return null; // un son manquant ne doit jamais casser une interaction
    } finally {
      loading.delete(clip);
    }
  })();

  loading.set(clip, task);
  return task;
}

/**
 * Construit l'AudioContext — JAMAIS dans un handler de geste.
 *
 * `new AudioContext()` initialise le matériel audio et BLOQUE le thread
 * principal le temps de le faire (mesuré ici à ~330 ms). Le faire dans le
 * premier `pointerdown` retardait d'autant la navigation qui suivait : le
 * sound design gelait littéralement le premier tap de la session.
 *
 * On le construit donc à l'inactivité. Il naît « suspended », ce qui est
 * permis hors geste — seul le `resume()` doit avoir lieu dans un geste.
 */
function ensureCtx(): AudioContext | null {
  if (ctx) return ctx;
  if (typeof window === "undefined") return null;
  const Ctor =
    window.AudioContext ??
    (window as unknown as { webkitAudioContext?: typeof AudioContext })
      .webkitAudioContext;
  if (!Ctor) return null;
  ctx = new Ctor();
  return ctx;
}

/** Réveille le contexte. Doit être appelé DANS un geste utilisateur (iOS). */
function resumeCtx() {
  const audio = ensureCtx();
  if (audio?.state === "suspended") void audio.resume();
}

export function initSound() {
  if (typeof window === "undefined") return;

  // Préparation hors du chemin critique : contexte + décodage des sons du geste.
  const warm = () => {
    if (!ensureCtx()) return;
    EAGER.forEach((c) => void load(c));
    setTimeout(() => {
      void load("levelup-1");
      void load("levelup-2");
      void load("boss-1");
      void load("boss-2");
    }, 3000);
  };
  const idle = (
    window as unknown as {
      requestIdleCallback?: (cb: () => void, o?: { timeout: number }) => void;
    }
  ).requestIdleCallback;
  if (idle) idle(warm, { timeout: 2500 });
  else setTimeout(warm, 800);

  // Le geste ne fait plus qu'un resume() : quelques microsecondes.
  const once = () => {
    resumeCtx();
    window.removeEventListener("pointerdown", once);
    window.removeEventListener("keydown", once);
  };
  window.addEventListener("pointerdown", once, { passive: true });
  window.addEventListener("keydown", once);
}

function play(clip: Clip, delayMs = 0) {
  if (typeof window === "undefined" || !soundEnabled()) return;

  resumeCtx();
  const audio = ctx;
  if (!audio) return;

  // Chemin chaud : le buffer est déjà décodé, on joue sans passer par une
  // micro-tâche — le son part dans le geste, pas une frame plus tard.
  const ready = buffers.get(clip);
  if (ready) {
    emit(audio, ready, clip, delayMs);
    return;
  }

  void load(clip).then((buf) => {
    if (buf) emit(audio, buf, clip, delayMs);
  });
}

function emit(
  audio: AudioContext,
  buf: AudioBuffer,
  clip: Clip,
  delayMs: number,
) {
  if (audio.state !== "running") return;
  const src = audio.createBufferSource();
  src.buffer = buf;
  const gain = audio.createGain();
  gain.gain.value = GAIN[clip];
  src.connect(gain).connect(audio.destination);
  src.start(audio.currentTime + delayMs / 1000);
}

function pick<T>(items: readonly T[]): T {
  return items[Math.floor(Math.random() * items.length)];
}

/* ------------------------------------------------------------------ */
/* API                                                                 */
/* ------------------------------------------------------------------ */

/** Navigation, boutons. Trois variantes tirées au hasard : répété des dizaines
 *  de fois par jour, un son stricement identique devient vite une nuisance. */
export function playTap() {
  play(pick(["tap-1", "tap-2", "tap-3"] as const));
}

export function playOpen() {
  play("open");
}

export function playClose() {
  play("close");
}

export function playError() {
  play("error");
}

/**
 * Validation d'une quête — le son signature de l'app.
 *
 * Les 3 sons ne sont PAS tirés au hasard : ils forment une montée sur la
 * journée. Premier check → check-1. Checks suivants → check-2. Et le check qui
 * vide la liste (journée parfaite) → check-3, qu'on n'entend donc qu'une fois
 * par jour, et seulement en allant au bout. Le hasard n'aurait rien raconté ;
 * là, l'oreille apprend que le 3e son veut dire « c'est plié ».
 */
export function playCheck({
  isLastOfDay,
  isFirstOfDay,
}: {
  isLastOfDay: boolean;
  isFirstOfDay: boolean;
}) {
  if (isLastOfDay) play("check-3");
  else if (isFirstOfDay) play("check-1");
  else play("check-2");
}

/**
 * Montée de niveau. Les paliers ronds (10, 20, 30…) ont leur propre fanfare :
 * ils doivent s'entendre comme un événement d'un autre ordre.
 *
 * Pas de délai ici — l'appelant le joue à la réception de la réponse serveur,
 * donc bien après que le son de check a fini de sonner.
 */
export function playLevelUp(newLevel: number) {
  play(newLevel % 10 === 0 ? "levelup-2" : "levelup-1");
}

/** Apparition / coup de boss. Alterné au hasard pour éviter la lassitude. */
export function playBoss() {
  play(pick(["boss-1", "boss-2"] as const));
}

/**
 * Retour haptique sur les interactions.
 *
 * Deux chemins, car il n'existe pas d'API unique :
 *
 * 1. **Android / Chrome** → API Vibration standard (`navigator.vibrate`).
 *
 * 2. **iOS / Safari** → l'API Vibration N'EXISTE PAS. Mais depuis Safari 17.4,
 *    le contrôle `<input type="checkbox" switch>` déclenche un vrai retour
 *    haptique natif quand il bascule. On garde donc un switch invisible dans
 *    le DOM et on le « clique » par programme : l'iPhone vibre.
 *    Contraintes : l'élément doit être RENDU (pas `display:none`), et l'appel
 *    doit se faire dans le contexte d'un geste utilisateur — ce qui est le cas
 *    (on n'appelle haptic() que depuis des onClick).
 *    Nécessite aussi que « Vibrations système » soit activé dans les réglages iOS.
 */
export type HapticKind = "tap" | "success" | "warn";

const PATTERNS: Record<HapticKind, number | number[]> = {
  tap: 10,
  success: [14, 30, 22],
  warn: [30, 40, 30],
};

let switchEl: HTMLInputElement | null = null;

/** Switch invisible mais RENDU (opacity 0 + hors écran, jamais display:none). */
function getHapticSwitch(): HTMLInputElement | null {
  if (typeof document === "undefined") return null;
  if (switchEl?.isConnected) return switchEl;

  const el = document.createElement("input");
  el.type = "checkbox";
  el.setAttribute("switch", ""); // Safari 17.4+ : rend un vrai switch iOS
  el.setAttribute("aria-hidden", "true");
  el.tabIndex = -1;
  el.style.cssText =
    "position:fixed;top:0;left:0;width:1px;height:1px;opacity:0;pointer-events:none;z-index:-1;";
  document.body.appendChild(el);
  switchEl = el;
  return el;
}

export function haptic(kind: HapticKind = "tap") {
  if (typeof navigator === "undefined") return;

  const nav = navigator as Navigator & {
    vibrate?: (p: number | number[]) => boolean;
  };

  // Android / Chrome
  if (typeof nav.vibrate === "function") {
    try {
      nav.vibrate(PATTERNS[kind]);
      return;
    } catch {
      /* on tente le fallback */
    }
  }

  // iOS / Safari (17.4+)
  try {
    getHapticSwitch()?.click();
  } catch {
    /* no-op : le retour visuel + sonore prend le relais */
  }
}

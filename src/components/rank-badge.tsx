type HunterRank = "E" | "D" | "C" | "B" | "A" | "S";

type Tone = { ring: string; glow: string; text: string; bg: string };

/** Teinte par rang (SPEC §3.3) : la progression E→S réchauffe le glow, S vire à l'or. */
const RANK_TONE: Record<HunterRank, Tone> = {
  E: { ring: "rgba(139,138,163,0.7)", glow: "rgba(139,138,163,0.4)", text: "#c9c8db", bg: "rgba(139,138,163,0.1)" },
  D: { ring: "rgba(34,211,238,0.6)", glow: "rgba(34,211,238,0.4)", text: "#22d3ee", bg: "rgba(34,211,238,0.1)" },
  C: { ring: "rgba(34,211,238,0.75)", glow: "rgba(34,211,238,0.5)", text: "#67e8f9", bg: "rgba(34,211,238,0.12)" },
  B: { ring: "rgba(124,58,237,0.75)", glow: "rgba(124,58,237,0.55)", text: "#b794f6", bg: "rgba(124,58,237,0.14)" },
  A: { ring: "rgba(157,92,255,0.85)", glow: "rgba(157,92,255,0.65)", text: "#c9a4ff", bg: "rgba(124,58,237,0.18)" },
  S: { ring: "rgba(245,158,11,0.9)", glow: "rgba(245,158,11,0.7)", text: "#fbbf24", bg: "rgba(245,158,11,0.16)" },
};

/** Malus visible (SPEC §3.16) : à partir de l'état 2 l'aura vire au gris, à
 * l'état 3 (boss actif) au rouge. Les fissures s'ajoutent dès l'état 1. */
const DAMAGE_TONE: Record<2 | 3, Tone> = {
  2: { ring: "rgba(139,138,163,0.85)", glow: "rgba(139,138,163,0.45)", text: "#b9b8c9", bg: "rgba(139,138,163,0.12)" },
  3: { ring: "rgba(239,68,68,0.9)", glow: "rgba(239,68,68,0.6)", text: "#fca5a5", bg: "rgba(239,68,68,0.14)" },
};

const DAMAGE_LABEL: Record<0 | 1 | 2 | 3, string> = {
  0: "Blason intact",
  1: "Fissures légères",
  2: "Fissures profondes",
  3: "Blason corrompu",
};

/**
 * Blason du Chasseur (SPEC §3.16) — « avatar V1 = blason héraldique par rang ».
 * C'est le MÊME objet que le badge de rang : il porte la lettre du rang ET
 * reflète le malus visible (fissures + aura qui vire au gris puis au rouge).
 */
export function RankBadge({
  rank,
  emblemDamage = 0,
  size = 76,
}: {
  rank: HunterRank;
  emblemDamage?: number;
  size?: number;
}) {
  const dmg = Math.max(0, Math.min(3, Math.round(emblemDamage))) as 0 | 1 | 2 | 3;
  const tone = dmg >= 3 ? DAMAGE_TONE[3] : dmg >= 2 ? DAMAGE_TONE[2] : RANK_TONE[rank];
  const crack = dmg >= 3 ? "#fecaca" : "#dcdbe9";

  return (
    <div
      className="relative grid place-items-center"
      style={{ width: size, height: size }}
      title={`Rang ${rank} · ${DAMAGE_LABEL[dmg]}`}
    >
      <div
        className="absolute inset-0 clip-hex"
        style={{ background: tone.glow, filter: "blur(10px)", opacity: 0.7 }}
        aria-hidden
      />
      <div
        className="absolute inset-0 clip-hex transition-colors duration-500"
        style={{ background: tone.bg, boxShadow: `inset 0 0 0 2px ${tone.ring}` }}
        aria-hidden
      />

      {/* Fissures du malus visible */}
      {dmg >= 1 && (
        <svg viewBox="0 0 100 100" className="absolute inset-0 h-full w-full" aria-hidden>
          <line x1="58" y1="4" x2="40" y2="46" stroke={crack} strokeWidth="2.5" opacity="0.8" />
          {dmg >= 2 && (
            <line x1="40" y1="46" x2="56" y2="96" stroke={crack} strokeWidth="2.5" opacity="0.8" />
          )}
          {dmg >= 3 && (
            <line x1="40" y1="46" x2="94" y2="38" stroke={crack} strokeWidth="2.5" opacity="0.85" />
          )}
        </svg>
      )}

      <span className="relative flex flex-col items-center leading-none">
        <span
          className="font-display"
          style={{
            fontSize: size * 0.12,
            letterSpacing: "0.25em",
            color: tone.text,
            opacity: 0.85,
            marginBottom: size * 0.02,
          }}
        >
          RANG
        </span>
        <span
          className="font-display"
          style={{
            fontSize: size * 0.42,
            fontWeight: 800,
            color: tone.text,
            textShadow: `0 0 12px ${tone.glow}`,
            lineHeight: 1,
          }}
        >
          {rank}
        </span>
      </span>
    </div>
  );
}

export { DAMAGE_LABEL };

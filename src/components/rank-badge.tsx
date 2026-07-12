type HunterRank = "E" | "D" | "C" | "B" | "A" | "S";

/** Teinte par rang (SPEC §3.3) : la progression E→S réchauffe le glow,
 * S vire à l'or (moment épique). */
const RANK_TONE: Record<HunterRank, { ring: string; glow: string; text: string; bg: string }> = {
  E: { ring: "rgba(139,138,163,0.7)", glow: "rgba(139,138,163,0.4)", text: "#c9c8db", bg: "rgba(139,138,163,0.1)" },
  D: { ring: "rgba(34,211,238,0.6)", glow: "rgba(34,211,238,0.4)", text: "#22d3ee", bg: "rgba(34,211,238,0.1)" },
  C: { ring: "rgba(34,211,238,0.75)", glow: "rgba(34,211,238,0.5)", text: "#67e8f9", bg: "rgba(34,211,238,0.12)" },
  B: { ring: "rgba(124,58,237,0.75)", glow: "rgba(124,58,237,0.55)", text: "#b794f6", bg: "rgba(124,58,237,0.14)" },
  A: { ring: "rgba(157,92,255,0.85)", glow: "rgba(157,92,255,0.65)", text: "#c9a4ff", bg: "rgba(124,58,237,0.18)" },
  S: { ring: "rgba(245,158,11,0.9)", glow: "rgba(245,158,11,0.7)", text: "#fbbf24", bg: "rgba(245,158,11,0.16)" },
};

/**
 * Badge de rang hexagonal (SPEC §3.3 / §9.2). Pièce de signature du Hub et
 * du Profil — hexagone lumineux, lettre en typo display.
 */
export function RankBadge({
  rank,
  size = 76,
}: {
  rank: HunterRank;
  size?: number;
}) {
  const tone = RANK_TONE[rank];
  return (
    <div
      className="relative grid place-items-center"
      style={{ width: size, height: size }}
    >
      {/* halo externe */}
      <div
        className="absolute inset-0 clip-hex"
        style={{ background: tone.glow, filter: "blur(10px)", opacity: 0.7 }}
        aria-hidden
      />
      {/* corps */}
      <div
        className="absolute inset-0 clip-hex"
        style={{ background: tone.bg, boxShadow: `inset 0 0 0 2px ${tone.ring}` }}
        aria-hidden
      />
      <span
        className="font-display relative"
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
    </div>
  );
}

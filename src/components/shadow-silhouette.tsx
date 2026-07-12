export type ShadowGrade = "soldat" | "chevalier" | "general" | "marechal";

const GRADE_LABELS: Record<ShadowGrade, string> = {
  soldat: "Soldat",
  chevalier: "Chevalier",
  general: "Général",
  marechal: "Maréchal",
};

type Tone = "violet" | "ghost";

const TONE_COLORS: Record<Tone, { fill: string; eyes: string; glow: string }> = {
  violet: { fill: "#0b0a12", eyes: "#7C3AED", glow: "rgba(124,58,237,0.55)" },
  ghost: { fill: "#0b0f1a", eyes: "#93C5FD", glow: "rgba(147,197,253,0.45)" },
};

/**
 * Silhouette d'Ombre (SPEC §3.11) : 1 forme de base + accents par grade
 * (épaulettes, cape, couronne), en SVG codé à la main — pas d'asset externe
 * (cf. planche de référence dans design/mockups/). Même silhouette recolorée
 * en `ghost` pour le Fantôme (§3.12).
 */
export function ShadowSilhouette({
  grade,
  tone = "violet",
  size = 72,
  showLabel = true,
}: {
  grade: ShadowGrade;
  tone?: Tone;
  size?: number;
  showLabel?: boolean;
}) {
  const c = TONE_COLORS[tone];

  return (
    <div className="flex flex-col items-center gap-1">
      <svg
        width={size}
        height={size}
        viewBox="0 0 64 64"
        style={{ filter: `drop-shadow(0 0 6px ${c.glow})` }}
        aria-label={GRADE_LABELS[grade]}
      >
        {/* Cape (Général, Maréchal) — derrière le corps */}
        {(grade === "general" || grade === "marechal") && (
          <path d="M 20 26 L 8 56 L 32 50 L 56 56 L 44 26 Z" fill={c.fill} opacity={0.85} />
        )}

        {/* Tête */}
        <circle cx="32" cy="18" r="9" fill={c.fill} />

        {/* Corps */}
        <path d="M 20 30 Q 32 24 44 30 L 40 54 L 24 54 Z" fill={c.fill} />

        {/* Épaulettes (Chevalier, Général, Maréchal) */}
        {grade !== "soldat" && (
          <>
            <path d="M 17 28 L 24 26 L 22 34 L 15 33 Z" fill={c.fill} />
            <path d="M 47 28 L 40 26 L 42 34 L 49 33 Z" fill={c.fill} />
          </>
        )}

        {/* Couronne (Maréchal uniquement) */}
        {grade === "marechal" && (
          <path
            d="M 24 9 L 26 3 L 29 8 L 32 2 L 35 8 L 38 3 L 40 9 Z"
            fill={c.fill}
          />
        )}

        {/* Yeux lumineux */}
        <circle cx="28" cy="18" r="1.6" fill={c.eyes} />
        <circle cx="36" cy="18" r="1.6" fill={c.eyes} />
      </svg>
      {showLabel && <span className="text-[10px] text-text-muted">{GRADE_LABELS[grade]}</span>}
    </div>
  );
}

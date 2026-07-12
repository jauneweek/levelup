import { STAT_LABELS, type StatCode } from "@/lib/xp";

/** Ordre horaire depuis le sommet (SPEC §3.1 / mockup Hub) :
 * FOR haut, INT haut-droite, PRO bas-droite, SAG bas-gauche, END haut-gauche. */
const AXES: StatCode[] = ["FOR", "INT", "PRO", "SAG", "END"];

type Pt = { x: number; y: number };

function vertex(cx: number, cy: number, r: number, index: number): Pt {
  const angle = (-90 + index * 72) * (Math.PI / 180);
  return { x: cx + r * Math.cos(angle), y: cy + r * Math.sin(angle) };
}

function polygon(cx: number, cy: number, r: number, fractions?: number[]): string {
  return AXES.map((_, i) => {
    const f = fractions ? fractions[i] : 1;
    const p = vertex(cx, cy, r * f, i);
    return `${p.x.toFixed(1)},${p.y.toFixed(1)}`;
  }).join(" ");
}

/**
 * Radar pentagone des 5 statistiques (mockup Hub). Rendu SVG pur (aucun JS
 * client). Les niveaux sont normalisés sur la stat la plus haute : la forme
 * montre l'équilibre du build, comme sur la maquette de référence.
 */
export function StatRadar({
  levels,
  size = 240,
}: {
  levels: Record<StatCode, number>;
  size?: number;
}) {
  const cx = size / 2;
  const cy = size / 2;
  const R = size * 0.32;
  const maxLevel = Math.max(1, ...AXES.map((s) => levels[s] ?? 1));
  const fractions = AXES.map((s) => {
    const lvl = levels[s] ?? 1;
    // plancher visuel : même à bas niveau la forme reste lisible
    return 0.16 + 0.84 * (lvl / maxLevel);
  });

  return (
    <svg
      width={size}
      height={size}
      viewBox={`0 0 ${size} ${size}`}
      role="img"
      aria-label="Radar des cinq statistiques"
    >
      <defs>
        <radialGradient id="radar-fill" cx="50%" cy="45%" r="60%">
          <stop offset="0%" stopColor="#22d3ee" stopOpacity="0.55" />
          <stop offset="100%" stopColor="#7c3aed" stopOpacity="0.45" />
        </radialGradient>
      </defs>

      {/* anneaux de grille */}
      {[0.34, 0.67, 1].map((ring) => (
        <polygon
          key={ring}
          points={polygon(cx, cy, R, AXES.map(() => ring))}
          fill="none"
          stroke="rgba(124,58,237,0.18)"
          strokeWidth={1}
        />
      ))}

      {/* rayons */}
      {AXES.map((_, i) => {
        const p = vertex(cx, cy, R, i);
        return (
          <line
            key={i}
            x1={cx}
            y1={cy}
            x2={p.x}
            y2={p.y}
            stroke="rgba(124,58,237,0.14)"
            strokeWidth={1}
          />
        );
      })}

      {/* données */}
      <polygon
        points={polygon(cx, cy, R, fractions)}
        fill="url(#radar-fill)"
        stroke="#22d3ee"
        strokeWidth={1.5}
        style={{ filter: "drop-shadow(0 0 6px rgba(34,211,238,0.4))" }}
      />
      {AXES.map((s, i) => {
        const p = vertex(cx, cy, R * fractions[i], i);
        return <circle key={s} cx={p.x} cy={p.y} r={2.6} fill="#ededf7" />;
      })}

      {/* étiquettes — code de stat seul (le niveau précis vit dans les
          barres XP juste en dessous, on évite ainsi tout débordement) */}
      {AXES.map((s, i) => {
        const p = vertex(cx, cy, R + 14, i);
        const anchor = p.x < cx - 4 ? "end" : p.x > cx + 4 ? "start" : "middle";
        return (
          <text
            key={s}
            x={p.x}
            y={p.y}
            textAnchor={anchor}
            dominantBaseline="middle"
            style={{
              fontFamily: "var(--font-orbitron), sans-serif",
              fontSize: 11,
              letterSpacing: "0.1em",
              fill: "#b794f6",
            }}
          >
            {s}
            <title>{STAT_LABELS[s]}</title>
          </text>
        );
      })}
    </svg>
  );
}

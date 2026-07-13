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
  // 0.26 + étiquettes courtes : garantit que END/INT (les plus latérales) ne
  // débordent pas du SVG, quelle que soit la taille demandée.
  const R = size * 0.26;

  // Échelle ABSOLUE, pas relative à la stat la plus haute : un compte neuf
  // (toutes les stats au niveau 1) doit afficher un pentagone minuscule, pas
  // un radar maxé. Le plafond monte par paliers de 10 au fur et à mesure de
  // la progression.
  const maxLevel = Math.max(1, ...AXES.map((s) => levels[s] ?? 1));
  const ceiling = Math.max(10, Math.ceil(maxLevel / 10) * 10);
  const fractions = AXES.map((s) =>
    Math.max(0.04, Math.min(1, (levels[s] ?? 1) / ceiling)),
  );

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
          <stop offset="0%" stopColor="#22d3ee" stopOpacity="0.6" />
          <stop offset="60%" stopColor="#7c3aed" stopOpacity="0.5" />
          <stop offset="100%" stopColor="#7c3aed" stopOpacity="0.35" />
        </radialGradient>
        <radialGradient id="radar-core" cx="50%" cy="50%" r="50%">
          <stop offset="0%" stopColor="#e9d5ff" stopOpacity="0.9" />
          <stop offset="35%" stopColor="#22d3ee" stopOpacity="0.5" />
          <stop offset="100%" stopColor="#7c3aed" stopOpacity="0" />
        </radialGradient>
      </defs>

      {/* lueur centrale */}
      <circle cx={cx} cy={cy} r={R * 0.55} fill="url(#radar-core)" />

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
        const p = vertex(cx, cy, R + 12, i);
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
              fontSize: 10,
              letterSpacing: "0.05em",
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

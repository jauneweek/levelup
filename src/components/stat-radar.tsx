import { STAT_LABELS, type StatCode } from "@/lib/xp";

/** Ordre horaire depuis le sommet (SPEC §3.1 / mockup Hub). */
const AXES: StatCode[] = ["FOR", "INT", "PRO", "SAG", "END"];

/* Géométrie fixe : le SVG scale à 100 % de la box (width: 100%), donc le
 * radar remplit vraiment le panneau. Marges calculées pour que les étiquettes
 * latérales (END/INT) ne débordent jamais. */
const W = 344;
const H = 272;
const CX = 172;
const CY = 146;
const R = 122;
const LABEL = 13;

type Pt = { x: number; y: number };

function vertex(r: number, index: number): Pt {
  const a = (-90 + index * 72) * (Math.PI / 180);
  return { x: CX + r * Math.cos(a), y: CY + r * Math.sin(a) };
}

function polygon(fractions: number[]): string {
  return AXES.map((_, i) => {
    const p = vertex(R * fractions[i], i);
    return `${p.x.toFixed(1)},${p.y.toFixed(1)}`;
  }).join(" ");
}

/**
 * Radar pentagone des 5 statistiques. Rendu SVG pur (aucun JS client).
 *
 * Échelle ABSOLUE, pas relative à la stat la plus haute : un compte neuf
 * (toutes stats niveau 1) doit afficher un pentagone minuscule, pas un radar
 * maxé. Le plafond monte par paliers de 10 avec la progression.
 */
export function StatRadar({ levels }: { levels: Record<StatCode, number> }) {
  const maxLevel = Math.max(1, ...AXES.map((s) => levels[s] ?? 1));
  const ceiling = Math.max(10, Math.ceil(maxLevel / 10) * 10);
  const fractions = AXES.map((s) =>
    Math.max(0.04, Math.min(1, (levels[s] ?? 1) / ceiling)),
  );

  return (
    <svg
      viewBox={`0 0 ${W} ${H}`}
      width="100%"
      style={{ height: "auto", display: "block" }}
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

      <circle cx={CX} cy={CY} r={R * 0.55} fill="url(#radar-core)" />

      {[0.34, 0.67, 1].map((ring) => (
        <polygon
          key={ring}
          points={polygon(AXES.map(() => ring))}
          fill="none"
          stroke="rgba(124,58,237,0.18)"
          strokeWidth={1}
        />
      ))}

      {AXES.map((_, i) => {
        const p = vertex(R, i);
        return (
          <line
            key={i}
            x1={CX}
            y1={CY}
            x2={p.x}
            y2={p.y}
            stroke="rgba(124,58,237,0.14)"
            strokeWidth={1}
          />
        );
      })}

      <polygon
        points={polygon(fractions)}
        fill="url(#radar-fill)"
        stroke="#22d3ee"
        strokeWidth={1.8}
        style={{ filter: "drop-shadow(0 0 6px rgba(34,211,238,0.45))" }}
      />
      {AXES.map((s, i) => {
        const p = vertex(R * fractions[i], i);
        return <circle key={s} cx={p.x} cy={p.y} r={3.2} fill="#ededf7" />;
      })}

      {AXES.map((s, i) => {
        const p = vertex(R + LABEL, i);
        const anchor = p.x < CX - 4 ? "end" : p.x > CX + 4 ? "start" : "middle";
        return (
          <text
            key={s}
            x={p.x}
            y={p.y}
            textAnchor={anchor}
            dominantBaseline="middle"
            style={{
              fontFamily: "var(--font-orbitron), sans-serif",
              fontSize: 13,
              letterSpacing: "0.06em",
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

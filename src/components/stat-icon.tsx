import type { StatCode } from "@/lib/xp";

/** Glyphes de stats (SPEC §3.1 / planche d'assets) : muscle, livre, lotus,
 * mallette, lune — traits simples en hexagone lumineux. */
const GLYPHS: Record<StatCode, React.ReactNode> = {
  FOR: (
    <path d="M6 9 h3 l1.5 -2 h3 M14 7 c2 0 3 1 3 3 v1 c0 1.5 -1 2.5 -2.5 2.5 h-4 M8 9 v6 c0 1 .7 1.5 1.5 1.5 h2" />
  ),
  INT: (
    <>
      <path d="M4 6 c3 -1 5 -1 8 0 v11 c-3 -1 -5 -1 -8 0 Z" />
      <path d="M12 6 c3 -1 5 -1 8 0 v11 c-3 -1 -5 -1 -8 0" />
    </>
  ),
  SAG: (
    <>
      <path d="M12 7 c-2 2 -3 4 -3 6 c0 1.5 1.3 2.5 3 2.5 s3 -1 3 -2.5 c0 -2 -1 -4 -3 -6 Z" />
      <path d="M6 13 c1 2 3 3 6 3 s5 -1 6 -3" />
    </>
  ),
  PRO: (
    <>
      <rect x="4" y="8" width="16" height="10" rx="1.5" />
      <path d="M9 8 V6.5 c0 -.8 .5 -1.3 1.3 -1.3 h3.4 c.8 0 1.3 .5 1.3 1.3 V8" />
      <path d="M4 12 h16" />
    </>
  ),
  END: <path d="M17 13 a6 6 0 1 1 -6.5 -6 a5 5 0 0 0 6.5 6 Z" />,
};

export function StatIcon({
  stat,
  size = 34,
  className = "",
}: {
  stat: StatCode;
  size?: number;
  className?: string;
}) {
  return (
    <span
      className={`relative grid place-items-center clip-hex ${className}`}
      style={{
        width: size,
        height: size,
        background: "rgba(124,58,237,0.12)",
        boxShadow: "inset 0 0 0 1px rgba(124,58,237,0.5)",
      }}
    >
      <svg
        width={size * 0.62}
        height={size * 0.62}
        viewBox="0 0 24 24"
        fill="none"
        stroke="#b794f6"
        strokeWidth={1.5}
        strokeLinecap="round"
        strokeLinejoin="round"
        style={{ filter: "drop-shadow(0 0 3px rgba(124,58,237,0.6))" }}
      >
        {GLYPHS[stat]}
      </svg>
    </span>
  );
}

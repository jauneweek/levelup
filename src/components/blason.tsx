const STATE_STYLES: Record<0 | 1 | 2 | 3, { border: string; glow: string; fill: string; crack: string }> = {
  0: {
    border: "border-violet/70",
    glow: "shadow-[0_0_16px_rgba(124,58,237,0.5)]",
    fill: "bg-violet/10",
    crack: "#7C3AED",
  },
  1: {
    border: "border-violet/50",
    glow: "shadow-[0_0_10px_rgba(124,58,237,0.3)]",
    fill: "bg-violet/5",
    crack: "#8B8AA3",
  },
  2: {
    border: "border-text-muted/70",
    glow: "shadow-[0_0_10px_rgba(139,138,163,0.25)]",
    fill: "bg-white/5",
    crack: "#8B8AA3",
  },
  3: {
    border: "border-danger/70",
    glow: "shadow-[0_0_18px_rgba(239,68,68,0.55)]",
    fill: "bg-danger/10",
    crack: "#EF4444",
  },
};

const STATE_LABELS: Record<0 | 1 | 2 | 3, string> = {
  0: "Blason intact",
  1: "Fissures légères",
  2: "Fissures profondes",
  3: "Blason corrompu",
};

/**
 * Blason du Chasseur (SPEC §3.16) : hexagone dont l'aura reflète le malus
 * visible (0 = sain, 3 = boss actif). Indicateur statique volontairement
 * simple — les transitions/animations riches sont prévues en M7.
 */
export function Blason({ emblemDamage }: { emblemDamage: number }) {
  const state = Math.max(0, Math.min(3, Math.round(emblemDamage))) as 0 | 1 | 2 | 3;
  const style = STATE_STYLES[state];

  return (
    <div className="flex flex-col items-center gap-1.5">
      <div
        className={`relative h-14 w-14 border-2 ${style.border} ${style.glow} ${style.fill} transition-colors duration-500`}
        style={{ clipPath: "polygon(25% 0%, 75% 0%, 100% 50%, 75% 100%, 25% 100%, 0% 50%)" }}
      >
        {state >= 1 && (
          <svg viewBox="0 0 56 56" className="absolute inset-0 h-full w-full" aria-hidden>
            <line x1="30" y1="2" x2="21" y2="27" stroke={style.crack} strokeWidth="1.5" opacity="0.85" />
          </svg>
        )}
        {state >= 2 && (
          <svg viewBox="0 0 56 56" className="absolute inset-0 h-full w-full" aria-hidden>
            <line x1="21" y1="27" x2="31" y2="47" stroke={style.crack} strokeWidth="1.5" opacity="0.85" />
          </svg>
        )}
        {state >= 3 && (
          <svg viewBox="0 0 56 56" className="absolute inset-0 h-full w-full" aria-hidden>
            <line x1="21" y1="27" x2="42" y2="24" stroke={style.crack} strokeWidth="1.5" opacity="0.9" />
          </svg>
        )}
      </div>
      <span className="text-[10px] text-text-muted">{STATE_LABELS[state]}</span>
    </div>
  );
}

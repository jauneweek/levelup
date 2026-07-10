import type { ReactNode } from "react";

type HexChipProps = {
  children: ReactNode;
  tone?: "violet" | "cyan" | "amber" | "danger";
  className?: string;
};

const TONE_STYLES: Record<NonNullable<HexChipProps["tone"]>, string> = {
  violet: "bg-violet/20 text-violet border-violet/60",
  cyan: "bg-cyan/20 text-cyan border-cyan/60",
  amber: "bg-amber/20 text-amber border-amber/60",
  danger: "bg-danger/20 text-danger border-danger/60",
};

/**
 * Chip hexagonal (SPEC §9.2 : "hexagone partout... jamais de cercles pour
 * les éléments de jeu"). Utilisé pour les difficultés et le rang.
 */
export function HexChip({ children, tone = "violet", className = "" }: HexChipProps) {
  return (
    <span
      className={`inline-flex items-center justify-center border px-3 py-1 font-display text-xs ${TONE_STYLES[tone]} ${className}`}
      style={{ clipPath: "polygon(25% 0%, 75% 0%, 100% 50%, 75% 100%, 25% 100%, 0% 50%)" }}
    >
      {children}
    </span>
  );
}

export const DIFFICULTY_TONE = {
  easy: "cyan",
  medium: "amber",
  hard: "danger",
} as const;

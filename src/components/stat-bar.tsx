import { STAT_LABELS, xpToNextLevel, type StatCode } from "@/lib/xp";

export function StatBar({
  stat,
  level,
  currentXp,
}: {
  stat: StatCode;
  level: number;
  currentXp: number;
}) {
  const threshold = xpToNextLevel(level);
  const pct = Math.min(100, Math.round((currentXp / threshold) * 100));

  return (
    <div>
      <div className="flex items-baseline justify-between text-xs">
        <span className="text-text-muted">{STAT_LABELS[stat]}</span>
        <span className="font-display text-cyan">
          Niv. {level}
          <span className="ml-2 text-text-muted">
            {currentXp}/{threshold} XP
          </span>
        </span>
      </div>
      <div className="mt-1 h-1.5 w-full overflow-hidden rounded-full bg-black/40">
        <div
          className="h-full rounded-full bg-cyan transition-[width] duration-300"
          style={{ width: `${pct}%` }}
        />
      </div>
    </div>
  );
}

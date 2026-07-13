"use client";

import { useState, type ReactNode } from "react";
import { StatBar } from "@/components/stat-bar";
import { SystemModal } from "@/components/system-modal";
import { haptic } from "@/lib/haptics";
import type { StatCode } from "@/lib/xp";

const STAT_ORDER: StatCode[] = ["FOR", "INT", "SAG", "PRO", "END"];

export type StatEntry = { level: number; current_xp: number };

/** Le radar est tappable, ET un bouton hexagonal bien visible ouvre le détail. */
export function StatDetailModal({
  stats,
  children,
}: {
  stats: Record<StatCode, StatEntry>;
  children: ReactNode;
}) {
  const [open, setOpen] = useState(false);

  const show = () => {
    haptic("tap");
    setOpen(true);
  };

  return (
    <>
      <div className="relative">
        <button
          type="button"
          onClick={show}
          aria-label="Voir le détail des statistiques"
          className="focus-ring block w-full transition-opacity hover:opacity-90"
        >
          {children}
        </button>

        {/* Déclencheur explicite, gros et lumineux */}
        <button
          type="button"
          onClick={show}
          aria-label="Détail des statistiques"
          className="stat-expand focus-ring"
        >
          <svg viewBox="0 0 24 24" aria-hidden>
            <path d="M4 7h16M4 12h16M4 17h10" />
          </svg>
        </button>
      </div>

      {open && (
        <SystemModal title="Statistiques" onClose={() => setOpen(false)}>
          <div className="space-y-4">
            {STAT_ORDER.map((code) => (
              <StatBar
                key={code}
                stat={code}
                level={stats[code]?.level ?? 1}
                currentXp={stats[code]?.current_xp ?? 0}
              />
            ))}
          </div>
        </SystemModal>
      )}
    </>
  );
}

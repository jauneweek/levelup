"use client";

import { useEffect, useState, type ReactNode } from "react";
import { StatBar } from "@/components/stat-bar";
import type { StatCode } from "@/lib/xp";

const STAT_ORDER: StatCode[] = ["FOR", "INT", "SAG", "PRO", "END"];

export type StatEntry = { level: number; current_xp: number };

/**
 * Le radar lui-même est la cible : on tape dessus pour ouvrir le détail des
 * niveaux (pas de bouton en format texte). SPEC §9.2 : tout contenu modal
 * passe par la Fenêtre Système.
 */
export function StatDetailModal({
  stats,
  children,
}: {
  stats: Record<StatCode, StatEntry>;
  children: ReactNode;
}) {
  const [open, setOpen] = useState(false);

  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") setOpen(false);
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [open]);

  return (
    <>
      <button
        type="button"
        onClick={() => setOpen(true)}
        aria-label="Voir le détail des statistiques"
        className="focus-ring relative block w-full rounded-md transition-opacity hover:opacity-90"
      >
        <span className="flex justify-center">{children}</span>
        <span
          aria-hidden
          className="clip-hex absolute right-0 top-0 grid h-6 w-6 place-items-center bg-violet/25 text-[11px] text-cyan"
          style={{ boxShadow: "inset 0 0 0 1px rgba(124,58,237,0.6)" }}
        >
          ⤢
        </span>
      </button>

      {open && (
        <div
          role="dialog"
          aria-modal="true"
          aria-label="Détail des statistiques"
          onClick={() => setOpen(false)}
          className="fixed inset-0 z-50 grid place-items-center p-5"
          style={{ background: "rgba(5,5,10,0.82)", backdropFilter: "blur(4px)" }}
        >
          <section
            onClick={(e) => e.stopPropagation()}
            className="system-window sw-enter w-full max-w-sm p-6"
          >
            <span aria-hidden className="sw-corner sw-corner--tl" />
            <span aria-hidden className="sw-corner sw-corner--tr" />
            <span aria-hidden className="sw-corner sw-corner--bl" />
            <span aria-hidden className="sw-corner sw-corner--br" />

            <header className="sw-header">
              <h2 className="font-display text-lg text-text-primary">Statistiques</h2>
            </header>

            <div className="mt-5 space-y-3.5">
              {STAT_ORDER.map((code) => (
                <StatBar
                  key={code}
                  stat={code}
                  level={stats[code]?.level ?? 1}
                  currentXp={stats[code]?.current_xp ?? 0}
                />
              ))}
            </div>

            <button type="button" onClick={() => setOpen(false)} className="sys-cta mt-6 w-full">
              Fermer
            </button>
          </section>
        </div>
      )}
    </>
  );
}

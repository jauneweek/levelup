"use client";

import { useState, type ReactNode } from "react";

type Segment = { key: string; label: string };

/**
 * Basculeur segmenté (hexagones allongés, DA §9.2). Les panneaux sont
 * rendus côté serveur et passés en props ; ce composant ne gère que
 * l'affichage de l'onglet actif — zéro requête client.
 */
export function SegmentTabs({
  segments,
  panels,
  initial,
}: {
  segments: Segment[];
  panels: Record<string, ReactNode>;
  initial?: string;
}) {
  const [active, setActive] = useState(initial ?? segments[0].key);

  return (
    <div>
      <div className="mb-4 flex gap-1.5" role="tablist">
        {segments.map((s) => {
          const on = s.key === active;
          return (
            <button
              key={s.key}
              type="button"
              role="tab"
              aria-selected={on}
              onClick={() => setActive(s.key)}
              className={`focus-ring clip-hex-wide flex-1 py-2 text-center font-display text-xs uppercase tracking-widest transition-colors ${
                on
                  ? "border border-violet bg-violet/25 text-text-primary"
                  : "border border-violet/25 bg-panel/50 text-text-muted"
              }`}
            >
              {s.label}
            </button>
          );
        })}
      </div>
      {panels[active]}
    </div>
  );
}

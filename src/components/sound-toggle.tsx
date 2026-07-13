"use client";

import { useEffect, useState } from "react";
import { haptic } from "@/lib/haptics";
import { playCheck, setSoundEnabled, soundEnabled } from "@/lib/sound";

/**
 * Interrupteur du sound design.
 *
 * L'état initial est lu APRÈS le montage : `soundEnabled()` tape dans
 * localStorage, qui n'existe pas au rendu serveur. Le lire pendant le rendu
 * produirait un HTML serveur différent du premier rendu client — soit une
 * erreur d'hydratation, soit un interrupteur qui affiche le mauvais état.
 */
export function SoundToggle() {
  const [on, setOn] = useState(true);
  const [ready, setReady] = useState(false);

  useEffect(() => {
    setOn(soundEnabled());
    setReady(true);
  }, []);

  const toggle = () => {
    const next = !on;
    setOn(next);
    setSoundEnabled(next);
    haptic("tap");
    // On rallume : autant faire entendre tout de suite ce qu'on vient d'activer.
    if (next) playCheck({ isFirstOfDay: true, isLastOfDay: false });
  };

  return (
    <div className="flex items-center justify-between gap-4">
      <div className="min-w-0">
        <p className="text-sm text-text-primary">Sons du Système</p>
        <p className="mt-0.5 text-[11px] text-text-muted">
          Validation de quête, montée de niveau, apparition de boss.
        </p>
      </div>

      <button
        type="button"
        role="switch"
        aria-checked={ready ? on : undefined}
        aria-label="Sons du Système"
        onClick={toggle}
        className={`focus-ring relative h-7 w-12 shrink-0 rounded-full border transition-colors ${
          on
            ? "border-violet bg-violet/40"
            : "border-violet/25 bg-panel/60"
        }`}
      >
        <span
          className="absolute top-1/2 block h-5 w-5 -translate-y-1/2 rounded-full transition-all"
          style={{
            left: on ? "calc(100% - 22px)" : "2px",
            background: on ? "var(--violet)" : "var(--text-muted)",
            boxShadow: on ? "0 0 10px rgba(124,58,237,0.9)" : "none",
          }}
        />
      </button>
    </div>
  );
}

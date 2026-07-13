"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { HabitFormFields } from "@/app/habits/habit-form-fields";
import {
  createHabit,
  updateHabit,
  toggleHabitActive,
  deleteHabit,
} from "@/app/habits/actions";
import type { StatCode } from "@/lib/xp";

export type EditableHabit = {
  id: string;
  name: string;
  stat: StatCode;
  difficulty: "easy" | "medium" | "hard";
  deadline_time: string | null;
  minimal_version: string | null;
  active: boolean;
  schedule: { days: number[] };
};

/** Création / édition d'une quête récurrente, en Fenêtre Système (SPEC §9.2).
 * Remplace l'ancien panneau repliable « Gérer mes habitudes ». */
export function HabitModal({
  habit,
  onClose,
}: {
  habit?: EditableHabit;
  onClose: () => void;
}) {
  const router = useRouter();
  const isEdit = Boolean(habit);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && onClose();
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);

  async function after(fn: () => Promise<void>) {
    await fn();
    onClose();
    router.refresh();
  }

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-label={isEdit ? "Modifier la quête" : "Nouvelle quête"}
      onClick={onClose}
      className="fixed inset-0 z-50 grid place-items-center p-4"
      style={{ background: "rgba(5,5,10,0.85)", backdropFilter: "blur(4px)" }}
    >
      <section
        onClick={(e) => e.stopPropagation()}
        className="system-window sw-enter w-full max-w-sm overflow-y-auto p-6 thin-scroll"
        style={{ maxHeight: "82vh" }}
      >
        <span aria-hidden className="sw-corner sw-corner--tl" />
        <span aria-hidden className="sw-corner sw-corner--tr" />
        <span aria-hidden className="sw-corner sw-corner--bl" />
        <span aria-hidden className="sw-corner sw-corner--br" />

        <header className="sw-header">
          <h2 className="font-display text-lg text-text-primary">
            {isEdit ? "Modifier la quête" : "Nouvelle quête"}
          </h2>
        </header>

        <form
          className="mt-5"
          action={(fd) => after(async () => (isEdit ? updateHabit(fd) : createHabit(fd)))}
        >
          {isEdit && <input type="hidden" name="habit_id" value={habit!.id} />}
          <HabitFormFields
            idPrefix={isEdit ? `edit-${habit!.id}` : "new"}
            defaultValues={
              isEdit
                ? {
                    name: habit!.name,
                    stat: habit!.stat,
                    difficulty: habit!.difficulty,
                    deadline_time: habit!.deadline_time,
                    minimal_version: habit!.minimal_version,
                    days: habit!.schedule?.days,
                  }
                : undefined
            }
          />
          <button type="submit" className="sys-cta mt-5 w-full">
            {isEdit ? "Enregistrer" : "Créer la quête"}
          </button>
        </form>

        {isEdit && (
          <div className="mt-3 grid grid-cols-2 gap-2">
            <form action={(fd) => after(async () => toggleHabitActive(fd))}>
              <input type="hidden" name="habit_id" value={habit!.id} />
              <input
                type="hidden"
                name="next_active"
                value={(!habit!.active).toString()}
              />
              <button type="submit" className="sys-cta sys-cta--ghost w-full py-2 text-xs">
                {habit!.active ? "Désactiver" : "Activer"}
              </button>
            </form>
            <form action={(fd) => after(async () => deleteHabit(fd))}>
              <input type="hidden" name="habit_id" value={habit!.id} />
              <button
                type="submit"
                className="sys-cta sys-cta--ghost w-full py-2 text-xs hover:border-danger hover:text-danger"
              >
                Supprimer
              </button>
            </form>
          </div>
        )}

        <button
          type="button"
          onClick={onClose}
          className="focus-ring mt-4 w-full py-1 text-center text-xs text-text-muted hover:text-text-primary"
        >
          Annuler
        </button>
      </section>
    </div>
  );
}

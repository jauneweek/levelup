"use client";

import { useRouter } from "next/navigation";
import { SystemModal } from "@/components/system-modal";
import { HabitFormFields } from "@/app/habits/habit-form-fields";
import { createHabit, updateHabit, toggleHabitActive, deleteHabit } from "@/app/habits/actions";
import { haptic } from "@/lib/haptics";
import type { Recurrence } from "@/lib/recurrence";
import type { StatCode } from "@/lib/xp";

export type EditableHabit = {
  id: string;
  name: string;
  stat: StatCode;
  difficulty: "easy" | "medium" | "hard";
  deadline_time: string | null;
  minimal_version: string | null;
  active: boolean;
  recurrence: Recurrence;
  frequency: number;
  temporary: boolean;
};

/** Création / édition d'une quête récurrente (remplace le panneau repliable). */
export function HabitModal({
  habit,
  onClose,
}: {
  habit?: EditableHabit;
  onClose: () => void;
}) {
  const router = useRouter();
  const isEdit = Boolean(habit);

  async function after(fn: () => Promise<void>) {
    await fn();
    haptic("success");
    onClose();
    router.refresh();
  }

  return (
    <SystemModal title={isEdit ? "Modifier la quête" : "Nouvelle quête"} onClose={onClose}>
      <form action={(fd) => after(async () => (isEdit ? updateHabit(fd) : createHabit(fd)))}>
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
                  recurrence: habit!.recurrence,
                  frequency: habit!.frequency,
                  temporary: habit!.temporary,
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
            <input type="hidden" name="next_active" value={(!habit!.active).toString()} />
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
    </SystemModal>
  );
}

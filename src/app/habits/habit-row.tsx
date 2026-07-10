"use client";

import { useState } from "react";
import { HexChip, DIFFICULTY_TONE } from "@/components/hex-chip";
import { STAT_LABELS, DIFFICULTY_XP, type StatCode } from "@/lib/xp";
import { HabitFormFields } from "./habit-form-fields";
import { updateHabit, toggleHabitActive, deleteHabit } from "./actions";

type Habit = {
  id: string;
  name: string;
  stat: StatCode;
  difficulty: "easy" | "medium" | "hard";
  deadline_time: string | null;
  active: boolean;
  schedule: { days: number[] };
};

const DAY_LABELS: Record<number, string> = {
  1: "Lun",
  2: "Mar",
  3: "Mer",
  4: "Jeu",
  5: "Ven",
  6: "Sam",
  7: "Dim",
};

export function HabitRow({ habit }: { habit: Habit }) {
  const [editing, setEditing] = useState(false);

  if (editing) {
    return (
      <form
        action={async (fd) => {
          await updateHabit(fd);
          setEditing(false);
        }}
        className="rounded border border-border-glow p-4"
      >
        <input type="hidden" name="habit_id" value={habit.id} />
        <HabitFormFields
          idPrefix={`edit-${habit.id}`}
          defaultValues={{
            name: habit.name,
            stat: habit.stat,
            difficulty: habit.difficulty,
            deadline_time: habit.deadline_time,
            days: habit.schedule?.days,
          }}
        />
        <div className="mt-3 flex gap-2">
          <button
            type="submit"
            className="rounded bg-violet px-3 py-1.5 text-xs font-medium text-white hover:opacity-90"
          >
            Enregistrer
          </button>
          <button
            type="button"
            onClick={() => setEditing(false)}
            className="rounded border border-border-glow px-3 py-1.5 text-xs text-text-muted hover:text-text-primary"
          >
            Annuler
          </button>
        </div>
      </form>
    );
  }

  const days = (habit.schedule?.days ?? []).sort((a, b) => a - b);

  return (
    <div
      className={`flex flex-wrap items-center justify-between gap-3 rounded border border-border-glow p-4 ${
        habit.active ? "" : "opacity-50"
      }`}
    >
      <div>
        <p className="text-sm text-text-primary">{habit.name}</p>
        <p className="mt-1 text-xs text-text-muted">
          {STAT_LABELS[habit.stat]} · {days.map((d) => DAY_LABELS[d]).join(" ")}
          {habit.deadline_time ? ` · avant ${habit.deadline_time.slice(0, 5)}` : ""}
        </p>
      </div>

      <div className="flex items-center gap-2">
        <HexChip tone={DIFFICULTY_TONE[habit.difficulty]}>
          +{DIFFICULTY_XP[habit.difficulty]} XP
        </HexChip>

        <button
          onClick={() => setEditing(true)}
          className="rounded border border-border-glow px-2 py-1 text-xs text-text-muted hover:text-cyan"
        >
          Éditer
        </button>

        <form action={toggleHabitActive}>
          <input type="hidden" name="habit_id" value={habit.id} />
          <input type="hidden" name="next_active" value={(!habit.active).toString()} />
          <button className="rounded border border-border-glow px-2 py-1 text-xs text-text-muted hover:text-amber">
            {habit.active ? "Désactiver" : "Activer"}
          </button>
        </form>

        <form action={deleteHabit}>
          <input type="hidden" name="habit_id" value={habit.id} />
          <button className="rounded border border-border-glow px-2 py-1 text-xs text-text-muted hover:text-danger">
            Supprimer
          </button>
        </form>
      </div>
    </div>
  );
}

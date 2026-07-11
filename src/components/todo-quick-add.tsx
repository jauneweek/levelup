"use client";

import { useRef } from "react";
import { STAT_LABELS, type StatCode } from "@/lib/xp";
import { createTodo } from "@/app/todos/actions";

const inputClass =
  "w-full rounded border border-border-glow bg-black/30 px-3 py-2 text-sm text-text-primary placeholder:text-text-muted outline-none focus:border-cyan focus:ring-1 focus:ring-cyan";

const STATS = Object.keys(STAT_LABELS) as StatCode[];

export function TodoQuickAdd({ date }: { date: string }) {
  const formRef = useRef<HTMLFormElement>(null);

  return (
    <form
      ref={formRef}
      action={async (fd) => {
        await createTodo(fd);
        formRef.current?.reset();
      }}
      className="flex flex-wrap items-end gap-2"
    >
      <input type="hidden" name="date" value={date} />

      <div className="flex-1 space-y-1" style={{ minWidth: "10rem" }}>
        <label htmlFor="todo-title" className="text-xs text-text-muted">
          Todo pour demain
        </label>
        <input
          id="todo-title"
          name="title"
          required
          className={inputClass}
          placeholder="Ex. Préparer le rapport"
        />
      </div>

      <div className="space-y-1">
        <label htmlFor="todo-stat" className="text-xs text-text-muted">
          Stat
        </label>
        <select id="todo-stat" name="stat" defaultValue="PRO" className={inputClass}>
          {STATS.map((s) => (
            <option key={s} value={s}>
              {STAT_LABELS[s]}
            </option>
          ))}
        </select>
      </div>

      <div className="space-y-1">
        <label htmlFor="todo-difficulty" className="text-xs text-text-muted">
          Difficulté
        </label>
        <select id="todo-difficulty" name="difficulty" defaultValue="easy" className={inputClass}>
          <option value="easy">Facile · +10 XP</option>
          <option value="medium">Moyenne · +25 XP</option>
          <option value="hard">Difficile · +50 XP</option>
        </select>
      </div>

      <button
        type="submit"
        className="rounded bg-violet px-3 py-2 text-xs font-medium text-white hover:opacity-90"
      >
        Planifier
      </button>
    </form>
  );
}

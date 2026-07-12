"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { STAT_LABELS, type StatCode } from "@/lib/xp";
import { StatIcon } from "@/components/stat-icon";
import { completeHabit, completeHabitExpress } from "@/app/habits/actions";
import { completeTodo } from "@/app/todos/actions";

const REDUCED =
  typeof window !== "undefined" &&
  window.matchMedia("(prefers-reduced-motion: reduce)").matches;

type QuestCardProps = {
  id: string;
  kind: "habit" | "todo";
  name: string;
  stat: StatCode;
  xp: number;
  done: boolean;
  meta?: string;
  express?: string | null;
};

export function QuestCard({
  id,
  kind,
  name,
  stat,
  xp,
  done,
  meta,
  express,
}: QuestCardProps) {
  const router = useRouter();
  const [slashing, setSlashing] = useState(false);
  const [, startTransition] = useTransition();

  function run(action: (fd: FormData) => Promise<void>, field: string) {
    if (slashing || done) return;
    setSlashing(true);
    const delay = REDUCED ? 0 : 620;
    setTimeout(() => {
      const fd = new FormData();
      fd.set(field, id);
      startTransition(async () => {
        await action(fd);
        router.refresh();
      });
    }, delay);
  }

  const onCheck = () =>
    run(kind === "habit" ? completeHabit : completeTodo, kind === "habit" ? "habit_id" : "todo_id");
  const onExpress = () => run(completeHabitExpress, "habit_id");

  return (
    <div
      className={`relative flex items-center gap-2.5 overflow-hidden border p-3 ${
        done ? "border-white/5 opacity-45" : "border-border-glow bg-panel/40"
      } ${slashing ? "is-slashing" : ""}`}
    >
      {kind === "todo" ? (
        <span className="grid h-[30px] w-[30px] shrink-0 place-items-center text-base">📋</span>
      ) : (
        <StatIcon stat={stat} size={30} />
      )}

      <div className="min-w-0 flex-1">
        <p
          title={name}
          className={`truncate text-sm text-text-primary ${done ? "line-through" : ""}`}
        >
          {name}
        </p>
        <p className="truncate text-xs text-text-muted">
          {STAT_LABELS[stat]}
          {meta ? ` · ${meta}` : ""}
        </p>
      </div>

      {done ? (
        <span className="font-display shrink-0 text-xs tracking-wide text-cyan tabular-nums">
          ✓ +{xp}
        </span>
      ) : (
        <>
          <span className="font-display shrink-0 text-xs tracking-wide text-cyan tabular-nums">
            +{xp}
            <span className="ml-0.5 text-[10px] text-cyan/70">XP</span>
          </span>
          {express && (
            <button
              type="button"
              onClick={onExpress}
              title={`Donjon express : ${express}`}
              aria-label={`Donjon express de ${name} : ${express}`}
              className="focus-ring clip-hex grid h-7 w-7 shrink-0 place-items-center bg-amber/15 text-sm text-amber transition-colors hover:bg-amber/30"
            >
              ⚡
            </button>
          )}
          <button
            type="button"
            onClick={onCheck}
            aria-label={`Compléter ${name}`}
            className="focus-ring clip-hex grid h-7 w-7 shrink-0 place-items-center bg-violet/25 text-sm text-violet/60 transition-colors hover:bg-violet/45 hover:text-cyan"
          >
            ✓
          </button>
        </>
      )}

      <span className="slash-layer" aria-hidden />
      <span className="xp-float" aria-hidden>
        +{xp} XP
      </span>
    </div>
  );
}

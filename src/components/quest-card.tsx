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
      className={`relative flex items-center gap-3 overflow-hidden rounded-md border p-3.5 transition-colors ${
        done
          ? "border-white/5 opacity-45"
          : "border-border-glow bg-gradient-to-r from-violet/[0.07] to-transparent"
      } ${slashing ? "is-slashing" : ""}`}
    >
      {kind === "todo" ? (
        <span
          className="clip-hex grid h-9 w-9 shrink-0 place-items-center text-base"
          style={{ background: "rgba(124,58,237,0.12)", boxShadow: "inset 0 0 0 1px rgba(124,58,237,0.5)" }}
        >
          📋
        </span>
      ) : (
        <StatIcon stat={stat} size={36} />
      )}

      <div className="min-w-0 flex-1">
        <p
          title={name}
          className={`truncate text-[15px] text-text-primary ${done ? "line-through" : ""}`}
        >
          {name}
        </p>
        <p className="truncate text-xs">
          <span className="font-display tabular-nums text-cyan">+{xp} XP</span>
          <span className="text-text-muted">
            {" · "}
            {STAT_LABELS[stat]}
            {meta ? ` · ${meta}` : ""}
          </span>
        </p>
      </div>

      {done ? (
        <span className="font-display shrink-0 text-sm tracking-wide text-cyan tabular-nums">✓</span>
      ) : (
        <>
          {express && (
            <button
              type="button"
              onClick={onExpress}
              title={`Donjon express : ${express}`}
              aria-label={`Donjon express de ${name} : ${express}`}
              className="focus-ring clip-hex grid h-10 w-10 shrink-0 place-items-center bg-amber/15 text-base text-amber transition-colors hover:bg-amber/30"
              style={{ boxShadow: "inset 0 0 0 1.5px rgba(245,158,11,0.6)" }}
            >
              ⚡
            </button>
          )}
          <button
            type="button"
            onClick={onCheck}
            aria-label={`Compléter ${name}`}
            className="focus-ring clip-hex grid h-10 w-10 shrink-0 place-items-center bg-violet/25 text-base text-cyan transition-colors hover:bg-violet/50"
            style={{ boxShadow: "inset 0 0 0 1.5px rgba(124,58,237,0.75)" }}
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

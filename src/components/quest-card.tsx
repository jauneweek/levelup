"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { STAT_LABELS, type StatCode } from "@/lib/xp";
import { StatIcon } from "@/components/stat-icon";
import { completeHabit, completeHabitExpress } from "@/app/habits/actions";
import { completeTodo } from "@/app/todos/actions";
import type { CompleteResult } from "@/lib/complete-result";
import { RECURRENCE_SHORT, type Recurrence } from "@/lib/recurrence";
import { haptic } from "@/lib/haptics";
import { playCheck, playError, playLevelUp } from "@/lib/sound";

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
  /** Heure limite « HH:MM » — rendue en chip dédié, jamais tronquée. */
  deadline?: string | null;
  express?: string | null;
  /** Quota (M8). Absents pour une todo. */
  recurrence?: Recurrence;
  frequency?: number;
  doneInPeriod?: number;
  /** Quêtes déjà validées aujourd'hui, et restantes (celle-ci comprise).
   *  Sert à choisir le son de check : premier / courant / dernier du jour. */
  dayDone: number;
  dayPending: number;
  /** Ouvre l'édition (Quêtes uniquement). */
  onEdit?: () => void;
};

export function QuestCard({
  id,
  kind,
  name,
  stat,
  xp,
  done,
  deadline,
  express,
  recurrence,
  frequency = 1,
  doneInPeriod = 0,
  dayDone,
  dayPending,
  onEdit,
}: QuestCardProps) {
  const router = useRouter();
  /* Deux drapeaux distincts, et c'est volontaire :
     - `slashing` pilote l'ANIMATION ; elle a sa propre durée et ne doit rien
       devoir au réseau ;
     - `busy` est la GARDE anti double-envoi ; elle dure le temps de la requête.
     Les confondre rendait la carte inerte après le premier check — invisible
     tant qu'une quête se validait une seule fois, mais fatal avec un quota ×3. */
  const [slashing, setSlashing] = useState(false);
  const [busy, setBusy] = useState(false);
  const [, startTransition] = useTransition();

  function run(
    action: (fd: FormData) => Promise<CompleteResult | null>,
    field: string,
  ) {
    if (busy || done) return;

    // Retour immédiat, DANS le geste : haptique + son partent avant même que la
    // requête ne soit lancée. Un son qui attend le serveur n'est plus une
    // réponse au tap, c'est une notification — et ça se sent tout de suite.
    haptic("success");
    playCheck({ isFirstOfDay: dayDone === 0, isLastOfDay: dayPending <= 1 });

    setBusy(true);
    setSlashing(true);
    if (!REDUCED) setTimeout(() => setSlashing(false), 1000); // durée de l'anim

    setTimeout(
      () => {
        const fd = new FormData();
        fd.set(field, id);
        startTransition(async () => {
          try {
            const res = await action(fd);
            // La fanfare célèbre le CHASSEUR (la discipline), pas la stat : une
            // stat qui monte est fréquent et discret, un niveau de Chasseur est
            // l'événement. Un palier rond (10, 20, 30…) a sa propre fanfare.
            if (res?.hunterLeveledUp) playLevelUp(res.hunterLevelInRank);
            router.refresh();
          } catch {
            haptic("warn");
            playError();
          } finally {
            setBusy(false);
          }
        });
      },
      REDUCED ? 0 : 620,
    );
  }

  const onCheck = () =>
    run(
      kind === "habit" ? completeHabit : completeTodo,
      kind === "habit" ? "habit_id" : "todo_id",
    );

  return (
    <div
      className={`relative flex items-center gap-3 overflow-hidden rounded-md border p-3.5 transition-colors ${
        done
          ? "border-white/5 bg-transparent opacity-55"
          : "border-border-glow bg-gradient-to-r from-violet/[0.07] to-transparent"
      } ${slashing ? "is-slashing" : ""}`}
    >
      {kind === "todo" ? (
        <span
          className="clip-hex grid h-9 w-9 shrink-0 place-items-center text-base"
          style={{
            background: "rgba(124,58,237,0.12)",
            boxShadow: "inset 0 0 0 1px rgba(124,58,237,0.5)",
          }}
        >
          📋
        </span>
      ) : (
        <StatIcon stat={stat} size={36} />
      )}

      <button
        type="button"
        onClick={onEdit}
        disabled={!onEdit}
        className={`min-w-0 flex-1 text-left ${onEdit ? "focus-ring rounded" : "cursor-default"}`}
      >
        <p
          title={name}
          className={`truncate text-[15px] text-text-primary ${done ? "line-through" : ""}`}
        >
          {name}
        </p>
        {/* Chips : jamais de troncature sur le timing */}
        <span className="mt-1 flex flex-wrap items-center gap-1.5">
          <span className="quest-chip quest-chip--xp">+{xp} XP</span>
          <span className="quest-chip">{STAT_LABELS[stat]}</span>

          {/* Quota : n'a de sens à afficher que s'il vaut plus qu'une fois. */}
          {frequency > 1 && (
            <span className="quest-chip quest-chip--quota">
              {Math.min(doneInPeriod, frequency)}/{frequency}
            </span>
          )}
          {/* La récurrence ne s'affiche que si elle sort de l'ordinaire : tout
              écrire « Journalière » sur chaque carte serait du bruit. */}
          {recurrence && recurrence !== "daily" && (
            <span className="quest-chip">{RECURRENCE_SHORT[recurrence]}</span>
          )}

          {deadline && <span className="quest-chip quest-chip--time">⏱ {deadline}</span>}
          {kind === "todo" && <span className="quest-chip">todo</span>}
        </span>
      </button>

      {express && !done && (
        <button
          type="button"
          onClick={() => run(completeHabitExpress, "habit_id")}
          title={`Donjon express : ${express}`}
          aria-label={`Donjon express de ${name} : ${express}`}
          className="focus-ring clip-hex grid h-10 w-10 shrink-0 place-items-center bg-amber/12 text-base text-amber transition-colors hover:bg-amber/30"
          style={{ boxShadow: "inset 0 0 0 1.5px rgba(245,158,11,0.55)" }}
        >
          ⚡
        </button>
      )}

      {/* Check : état NEUTRE = hexagone CREUX (il appelle le tap) → une fois
          fait, hexagone PLEIN avec le ✓. En SVG : un clip-path découperait
          l'inset box-shadow et ne dessinerait pas l'anneau. */}
      <button
        type="button"
        onClick={onCheck}
        disabled={done}
        aria-label={done ? `${name} complétée` : `Compléter ${name}`}
        className={`quest-check focus-ring ${done ? "quest-check--done" : ""}`}
      >
        <svg viewBox="0 0 24 24" aria-hidden>
          <polygon
            className="hexline"
            points="12,1.6 22.4,6.8 22.4,17.2 12,22.4 1.6,17.2 1.6,6.8"
          />
          <path className="tick" d="M7.8 12.4l2.8 2.8 5.6-5.8" />
        </svg>
      </button>

      <span className="slash-layer" aria-hidden />
      <span className="xp-float" aria-hidden>
        +{xp} XP
      </span>
    </div>
  );
}

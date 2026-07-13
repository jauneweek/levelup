"use client";

import { useState } from "react";
import { STAT_LABELS, type StatCode } from "@/lib/xp";
import { PERIOD_NOUN, RECURRENCE_LABELS, type Recurrence } from "@/lib/recurrence";

const inputClass =
  "w-full rounded border border-border-glow bg-black/30 px-3 py-2 text-sm text-text-primary placeholder:text-text-muted outline-none focus:border-cyan focus:ring-1 focus:ring-cyan";

const STATS = Object.keys(STAT_LABELS) as StatCode[];
const RECURRENCES = Object.keys(RECURRENCE_LABELS) as Recurrence[];

const TEMPORARY_HINT: Record<Recurrence, string> = {
  daily: "Archivée dès ce soir : la période d'une quête journalière, c'est le jour même.",
  weekly: "Archivée dimanche soir, à la clôture de la semaine.",
  monthly: "Archivée à la fin du mois.",
  yearly: "Archivée à la fin de l'année.",
  once: "Sans effet ici : une quête unique disparaît déjà une fois accomplie.",
};

type HabitFormFieldsProps = {
  defaultValues?: {
    name?: string;
    stat?: StatCode;
    difficulty?: "easy" | "medium" | "hard";
    deadline_time?: string | null;
    minimal_version?: string | null;
    recurrence?: Recurrence;
    frequency?: number;
    temporary?: boolean;
  };
  idPrefix: string;
};

export function HabitFormFields({ defaultValues, idPrefix }: HabitFormFieldsProps) {
  const [recurrence, setRecurrence] = useState<Recurrence>(
    defaultValues?.recurrence ?? "daily",
  );
  const [frequency, setFrequency] = useState<number>(defaultValues?.frequency ?? 1);

  // Une quête unique se fait une fois, par définition : le quota n'a pas de sens.
  const showFrequency = recurrence !== "once";

  return (
    <div className="space-y-3">
      <div className="space-y-1">
        <label htmlFor={`${idPrefix}-name`} className="text-xs text-text-muted">
          Nom de la quête
        </label>
        <input
          id={`${idPrefix}-name`}
          name="name"
          required
          defaultValue={defaultValues?.name}
          className={inputClass}
          placeholder="Ex. 30 min de lecture"
        />
      </div>

      <div className="grid grid-cols-2 gap-3">
        <div className="space-y-1">
          <label htmlFor={`${idPrefix}-stat`} className="text-xs text-text-muted">
            Arc
          </label>
          <select
            id={`${idPrefix}-stat`}
            name="stat"
            defaultValue={defaultValues?.stat ?? "FOR"}
            className={inputClass}
          >
            {STATS.map((s) => (
              <option key={s} value={s}>
                {STAT_LABELS[s]}
              </option>
            ))}
          </select>
        </div>

        <div className="space-y-1">
          <label htmlFor={`${idPrefix}-difficulty`} className="text-xs text-text-muted">
            Difficulté
          </label>
          <select
            id={`${idPrefix}-difficulty`}
            name="difficulty"
            defaultValue={defaultValues?.difficulty ?? "easy"}
            className={inputClass}
          >
            <option value="easy">Facile · +10 XP</option>
            <option value="medium">Moyenne · +25 XP</option>
            <option value="hard">Difficile · +50 XP</option>
          </select>
        </div>
      </div>

      {/* ── Le quota : la mécanique centrale. Aucun jour n'est imposé. ── */}
      <div className="space-y-1">
        <label htmlFor={`${idPrefix}-recurrence`} className="text-xs text-text-muted">
          Récurrence
        </label>
        <select
          id={`${idPrefix}-recurrence`}
          name="recurrence"
          value={recurrence}
          onChange={(e) => setRecurrence(e.target.value as Recurrence)}
          className={inputClass}
        >
          {RECURRENCES.map((r) => (
            <option key={r} value={r}>
              {RECURRENCE_LABELS[r]}
            </option>
          ))}
        </select>
      </div>

      {showFrequency ? (
        <div className="space-y-1.5">
          <label htmlFor={`${idPrefix}-frequency`} className="text-xs text-text-muted">
            Fréquence —{" "}
            <b className="text-cyan">
              {frequency} fois par {PERIOD_NOUN[recurrence]}
            </b>
          </label>
          <input
            id={`${idPrefix}-frequency`}
            name="frequency"
            type="range"
            min={1}
            max={10}
            step={1}
            value={frequency}
            onChange={(e) => setFrequency(Number(e.target.value))}
            className="w-full accent-cyan"
          />
          <p className="text-[11px] leading-snug text-text-muted">
            Aucun jour n&apos;est imposé : la quête reste proposée tant que son quota
            de la période n&apos;est pas atteint.
          </p>
        </div>
      ) : (
        <input type="hidden" name="frequency" value={1} />
      )}

      <label className="flex items-start gap-2.5 rounded border border-border-glow px-3 py-2.5 text-xs text-text-muted has-[:checked]:border-cyan has-[:checked]:text-cyan">
        <input
          type="checkbox"
          name="temporary"
          value="true"
          defaultChecked={defaultValues?.temporary ?? false}
          className="mt-0.5 accent-cyan"
        />
        <span>
          Quête temporaire
          {/* On dit QUAND elle disparaît, pas « à la fin de sa période » : la
              période d'une quête journalière, c'est le jour même — une
              temporaire journalière s'archive donc ce soir. Personne ne devine
              ça tout seul. */}
          <span className="mt-0.5 block text-[11px] text-text-muted">
            {TEMPORARY_HINT[recurrence]}
          </span>
        </span>
      </label>

      <div className="space-y-1">
        <label htmlFor={`${idPrefix}-deadline`} className="text-xs text-text-muted">
          Heure limite (optionnel)
        </label>
        <input
          id={`${idPrefix}-deadline`}
          type="time"
          name="deadline_time"
          defaultValue={defaultValues?.deadline_time ?? ""}
          className={inputClass}
        />
        {recurrence !== "daily" && (
          <p className="text-[11px] leading-snug text-amber">
            Les rappels d&apos;heure limite ne concernent que les quêtes journalières —
            une quête {RECURRENCE_LABELS[recurrence].toLowerCase()} n&apos;est en retard
            aucun jour en particulier.
          </p>
        )}
      </div>

      <div className="space-y-1">
        <label htmlFor={`${idPrefix}-minimal`} className="text-xs text-text-muted">
          Version minimale (donjon express, optionnel)
        </label>
        <input
          id={`${idPrefix}-minimal`}
          name="minimal_version"
          defaultValue={defaultValues?.minimal_version ?? ""}
          className={inputClass}
          placeholder="Ex. 2 pages, 5 pompes, 2 min de méditation"
        />
      </div>
    </div>
  );
}

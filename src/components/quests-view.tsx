"use client";

import { useState } from "react";
import { SystemWindow } from "@/components/system-window";
import { QuestCard } from "@/components/quest-card";
import { Pips } from "@/components/pips";
import { HabitModal, type EditableHabit } from "@/components/habit-modal";
import { DIFFICULTY_XP, STAT_LABELS, type StatCode } from "@/lib/xp";
import { haptic } from "@/lib/haptics";

const STAT_ORDER: StatCode[] = ["FOR", "INT", "SAG", "PRO", "END"];

export type QuestHabit = EditableHabit & { done: boolean; scheduledToday: boolean };
export type QuestTodo = {
  id: string;
  title: string;
  stat: StatCode;
  difficulty: "easy" | "medium" | "hard";
  done: boolean;
};
export type WeeklyQuest = {
  id: string;
  stat: StatCode;
  progress: number;
  target: number;
  reward: string;
};
export type BossState = { hp: number; maxHp: number; daysLeft: number } | null;

type Seg = "jour" | "hebdo" | "boss";

export function QuestsView({
  habits,
  todos,
  weekly,
  boss,
  expressLeft,
}: {
  habits: QuestHabit[];
  todos: QuestTodo[];
  weekly: WeeklyQuest[];
  boss: BossState;
  expressLeft: number;
}) {
  const [seg, setSeg] = useState<Seg>("jour");
  const [arc, setArc] = useState<StatCode | "ALL">("ALL");
  const [modal, setModal] = useState<{ habit?: EditableHabit } | null>(null);

  const byArc = <T extends { stat: StatCode }>(xs: T[]) =>
    arc === "ALL" ? xs : xs.filter((x) => x.stat === arc);

  const today = byArc(habits.filter((h) => h.scheduledToday));
  const todosToday = byArc(todos);
  const pending = [
    ...today.filter((h) => !h.done),
    ...todosToday.filter((t) => !t.done),
  ];
  const done = [...today.filter((h) => h.done), ...todosToday.filter((t) => t.done)];

  const segments: { key: Seg; label: string }[] = [
    { key: "jour", label: "Quotidiennes" },
    { key: "hebdo", label: "Hebdo" },
    { key: "boss", label: "Boss" },
  ];

  return (
    <div className="space-y-4">
      {/* Récurrence */}
      <div className="flex gap-1.5" role="tablist" aria-label="Récurrence">
        {segments.map((s) => {
          const on = s.key === seg;
          return (
            <button
              key={s.key}
              type="button"
              role="tab"
              aria-selected={on}
              onClick={() => {
                haptic("tap");
                setSeg(s.key);
              }}
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

      {/* Arc = filtre par domaine, en menu déroulant */}
      {seg === "jour" && (
        <label className="block">
          <span className="sr-only">Filtrer par arc</span>
          <select
            className="sys-select"
            value={arc}
            onChange={(e) => {
              haptic("tap");
              setArc(e.target.value as StatCode | "ALL");
            }}
          >
            <option value="ALL">Tous les arcs</option>
            {STAT_ORDER.map((s) => (
              <option key={s} value={s}>
                {STAT_LABELS[s]}
              </option>
            ))}
          </select>
        </label>
      )}

      {/* ── Quotidiennes ── */}
      {seg === "jour" && (
        <SystemWindow title="Aujourd'hui" showSystemTag={false}>
          {pending.length + done.length === 0 ? (
            <p className="text-sm text-text-muted">
              Aucune quête ici. Touche le « + » pour en créer une.
            </p>
          ) : (
            <div className="space-y-2">
              {pending.map((q) =>
                "name" in q ? (
                  <QuestCard
                    key={q.id}
                    id={q.id}
                    kind="habit"
                    name={q.name}
                    stat={q.stat}
                    xp={DIFFICULTY_XP[q.difficulty]}
                    done={false}
                    deadline={q.deadline_time ? q.deadline_time.slice(0, 5) : null}
                    express={q.minimal_version}
                    onEdit={() => {
                      haptic("tap");
                      setModal({ habit: q });
                    }}
                  />
                ) : (
                  <QuestCard
                    key={q.id}
                    id={q.id}
                    kind="todo"
                    name={q.title}
                    stat={q.stat}
                    xp={DIFFICULTY_XP[q.difficulty]}
                    done={false}
                  />
                ),
              )}
              {done.map((q) =>
                "name" in q ? (
                  <QuestCard
                    key={q.id}
                    id={q.id}
                    kind="habit"
                    name={q.name}
                    stat={q.stat}
                    xp={DIFFICULTY_XP[q.difficulty]}
                    done
                    deadline={q.deadline_time ? q.deadline_time.slice(0, 5) : null}
                    onEdit={() => {
                      haptic("tap");
                      setModal({ habit: q });
                    }}
                  />
                ) : (
                  <QuestCard
                    key={q.id}
                    id={q.id}
                    kind="todo"
                    name={q.title}
                    stat={q.stat}
                    xp={DIFFICULTY_XP[q.difficulty]}
                    done
                  />
                ),
              )}
            </div>
          )}
          <p className="mt-3 text-center text-xs text-text-muted">
            Donjon express restant : <b className="text-amber">{expressLeft}/2</b>
          </p>
        </SystemWindow>
      )}

      {/* ── Hebdo ── */}
      {seg === "hebdo" && (
        <>
          {weekly.length === 0 ? (
            <SystemWindow title="Quêtes hebdomadaires" showSystemTag={false}>
              <p className="text-sm text-text-muted">
                Le Système génère tes quêtes de la semaine chaque lundi.
              </p>
            </SystemWindow>
          ) : (
            weekly.map((q) => (
              <SystemWindow key={q.id} title="Quête hebdomadaire" showSystemTag={false}>
                <div className="flex items-baseline justify-between">
                  <span className="text-sm text-text-primary">
                    {q.target} quêtes de {STAT_LABELS[q.stat]}
                  </span>
                  <b className="font-display tabular-nums text-cyan">
                    {q.progress}/{q.target}
                  </b>
                </div>
                <div className="mt-3">
                  <Pips filled={q.progress} total={q.target} />
                </div>
                <p className="mt-3 text-xs text-text-muted">
                  Récompense : <span className="text-amber">{q.reward}</span>
                </p>
              </SystemWindow>
            ))
          )}
        </>
      )}

      {/* ── Boss ── */}
      {seg === "boss" && (
        <>
          {!boss ? (
            <SystemWindow title="Aucun Boss" showSystemTag={false}>
              <p className="text-sm text-text-muted">
                Le Boss de la Procrastination apparaît après 3 jours consécutifs sous 50 % de
                complétion. Tiens ton rythme et il restera enfermé.
              </p>
            </SystemWindow>
          ) : (
            <SystemWindow title="Boss de la Procrastination" tone="danger">
              <div className="flex items-center justify-between">
                <span className="font-display text-sm tracking-wider text-danger">
                  PV {boss.hp}/{boss.maxHp}
                </span>
                <span className="text-xs text-danger">J-{boss.daysLeft} avant sa fuite</span>
              </div>
              <div className="mt-3">
                <Pips filled={boss.hp} total={boss.maxHp} tone="hp" />
              </div>
              <p className="mt-3 text-xs text-text-muted">
                Arme : les journées parfaites. Chacune lui retire 1 PV. S&apos;il survit 14 jours,
                il dévore 10 % de ta meilleure stat.
              </p>
            </SystemWindow>
          )}
        </>
      )}

      {/* FAB — création de quête */}
      <button
        type="button"
        onClick={() => {
          haptic("tap");
          setModal({});
        }}
        className="fab"
        aria-label="Nouvelle quête"
      >
        +
      </button>

      {modal && <HabitModal habit={modal.habit} onClose={() => setModal(null)} />}
    </div>
  );
}

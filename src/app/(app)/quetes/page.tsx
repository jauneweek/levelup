import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { SystemWindow } from "@/components/system-window";
import { SegmentTabs } from "@/components/segment-tabs";
import { QuestCard } from "@/components/quest-card";
import { Pips } from "@/components/pips";
import { NewHabitForm } from "@/app/habits/new-habit-form";
import { HabitRow } from "@/app/habits/habit-row";
import { DIFFICULTY_XP, STAT_LABELS, type StatCode } from "@/lib/xp";
import { getDayState } from "@/lib/quests";

type WeeklyReward =
  | { type: "xp_bonus"; amount: number; stat: StatCode }
  | { type: "item"; rarity: string }
  | Record<string, unknown>;

function rewardLabel(reward: WeeklyReward): string {
  if ((reward as { type?: string }).type === "xp_bonus") {
    const r = reward as { amount: number; stat: StatCode };
    return `+${r.amount} XP ${r.stat}`;
  }
  if ((reward as { type?: string }).type === "item") {
    return `item ${(reward as { rarity: string }).rarity}`;
  }
  return "récompense";
}

export default async function QuetesPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect("/login");

  const day = await getDayState();
  const today = day?.today ?? "";

  const [{ count: expressCount }, { data: weekly }, { data: boss }, { data: allHabits }] =
    await Promise.all([
      supabase
        .from("habit_logs")
        .select("id", { count: "exact", head: true })
        .eq("date", today)
        .eq("is_express", true),
      supabase
        .from("quests")
        .select("id, definition, progress, target, reward")
        .eq("type", "weekly")
        .eq("status", "active"),
      supabase
        .from("boss_fights")
        .select("hp, max_hp, spawned_on")
        .eq("status", "active")
        .maybeSingle(),
      supabase
        .from("habits")
        .select("id, name, stat, difficulty, deadline_time, minimal_version, active, schedule")
        .order("created_at", { ascending: true }),
    ]);

  const pendingHabits = (day?.habits ?? []).filter((h) => !h.done);
  const doneHabits = (day?.habits ?? []).filter((h) => h.done);
  const pendingTodos = (day?.todos ?? []).filter((t) => !t.done);
  const doneTodos = (day?.todos ?? []).filter((t) => t.done);
  const nothingToday =
    pendingHabits.length + doneHabits.length + pendingTodos.length + doneTodos.length === 0;

  const expressUsed = expressCount ?? 0;

  let bossDaysLeft: number | null = null;
  if (boss?.spawned_on && today) {
    const age = Math.floor(
      (Date.parse(today) - Date.parse(boss.spawned_on)) / 86_400_000,
    );
    bossDaysLeft = Math.max(0, 14 - age);
  }

  // ── Panneau Aujourd'hui ──
  const jour = (
    <div className="space-y-4">
      <SystemWindow title="Aujourd'hui" showSystemTag={false}>
        {nothingToday ? (
          <p className="text-sm text-text-muted">
            Aucune quête programmée aujourd&apos;hui. Crée-en une ci-dessous.
          </p>
        ) : (
          <div className="space-y-2">
            {pendingHabits.map((h) => (
              <QuestCard
                key={h.id}
                id={h.id}
                kind="habit"
                name={h.name}
                stat={h.stat}
                xp={DIFFICULTY_XP[h.difficulty]}
                done={false}
                meta={h.deadline_time ? `avant ${h.deadline_time.slice(0, 5)}` : undefined}
                express={h.minimal_version}
              />
            ))}
            {pendingTodos.map((t) => (
              <QuestCard
                key={t.id}
                id={t.id}
                kind="todo"
                name={t.title}
                stat={t.stat}
                xp={DIFFICULTY_XP[t.difficulty]}
                done={false}
                meta="todo"
              />
            ))}
            {doneHabits.map((h) => (
              <QuestCard
                key={h.id}
                id={h.id}
                kind="habit"
                name={h.name}
                stat={h.stat}
                xp={DIFFICULTY_XP[h.difficulty]}
                done
              />
            ))}
            {doneTodos.map((t) => (
              <QuestCard
                key={t.id}
                id={t.id}
                kind="todo"
                name={t.title}
                stat={t.stat}
                xp={DIFFICULTY_XP[t.difficulty]}
                done
              />
            ))}
          </div>
        )}
        <p className="mt-3 text-center text-xs text-text-muted">
          Donjon express restant aujourd&apos;hui :{" "}
          <b className="text-amber">{Math.max(0, 2 - expressUsed)}/2</b>
        </p>
      </SystemWindow>

      <details className="system-window group p-0">
        <summary className="focus-ring flex cursor-pointer list-none items-center justify-between p-5 font-display text-sm uppercase tracking-widest text-text-primary">
          <span>Gérer mes habitudes</span>
          <span className="text-violet transition-transform group-open:rotate-90">›</span>
        </summary>
        <div className="space-y-4 px-5 pb-5">
          <div>
            <p className="mb-2 text-xs text-text-muted">Nouvelle habitude récurrente</p>
            <NewHabitForm />
          </div>
          {allHabits && allHabits.length > 0 && (
            <div className="space-y-3 border-t border-border-glow/40 pt-4">
              {allHabits.map((h) => (
                <HabitRow key={h.id} habit={h} />
              ))}
            </div>
          )}
        </div>
      </details>
    </div>
  );

  // ── Panneau Hebdo ──
  const hebdo = (
    <div className="space-y-4">
      {(weekly ?? []).length === 0 ? (
        <SystemWindow title="Quêtes hebdomadaires" showSystemTag={false}>
          <p className="text-sm text-text-muted">
            Tes quêtes de la semaine sont générées chaque lundi. Reviens lundi matin.
          </p>
        </SystemWindow>
      ) : (
        (weekly ?? []).map((q) => {
          const stat = (q.definition as { stat: StatCode }).stat;
          return (
            <SystemWindow key={q.id} title="Quête hebdomadaire" showSystemTag={false}>
              <div className="flex items-baseline justify-between">
                <span className="text-sm text-text-primary">
                  {q.target} habitudes de {STAT_LABELS[stat]}
                </span>
                <b className="font-display tabular-nums text-cyan">
                  {q.progress}/{q.target}
                </b>
              </div>
              <div className="mt-3">
                <Pips filled={q.progress} total={q.target} />
              </div>
              <p className="mt-3 text-xs text-text-muted">
                Récompense : <span className="text-amber">{rewardLabel(q.reward as WeeklyReward)}</span>
              </p>
            </SystemWindow>
          );
        })
      )}

      {boss && (
        <SystemWindow title="Boss de la Procrastination" tone="danger">
          <div className="flex items-center justify-between">
            <span className="font-display text-sm tracking-wider text-danger">
              PV {boss.hp}/{boss.max_hp}
            </span>
            {bossDaysLeft !== null && (
              <span className="text-xs text-danger">J-{bossDaysLeft} avant sa fuite</span>
            )}
          </div>
          <div className="mt-3">
            <Pips filled={boss.hp} total={boss.max_hp} tone="hp" />
          </div>
          <p className="mt-3 text-xs text-text-muted">
            Arme : les journées parfaites. Chacune lui retire 1 PV. S&apos;il survit 14 jours, il
            dévore 10 % de ta meilleure stat.
          </p>
        </SystemWindow>
      )}
    </div>
  );

  return (
    <div className="space-y-5">
      <div className="flex items-baseline justify-between px-1">
        <h1 className="font-display text-xl uppercase tracking-widest text-text-primary">Quêtes</h1>
        <span className="font-display text-xs tracking-[0.3em] text-violet">[SYSTÈME]</span>
      </div>
      <SegmentTabs
        segments={[
          { key: "jour", label: "Aujourd'hui" },
          { key: "hebdo", label: "Hebdo" },
        ]}
        panels={{ jour, hebdo }}
      />
    </div>
  );
}

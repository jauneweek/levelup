import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { getSessionUser } from "@/lib/auth";
import {
  QuestsView,
  type QuestHabit,
  type QuestTodo,
  type WeeklyQuest,
  type BossState,
} from "@/components/quests-view";
import { type StatCode } from "@/lib/xp";
import { getDayState } from "@/lib/quests";
import { todayInTimezone } from "@/lib/date";

function rewardLabel(reward: Record<string, unknown>): string {
  if (reward?.type === "xp_bonus") return `+${reward.amount} XP ${reward.stat}`;
  if (reward?.type === "item") return `objet ${reward.rarity}`;
  return "récompense";
}

export default async function QuetesPage() {
  const supabase = await createClient();
  const user = await getSessionUser();
  if (!user) redirect("/login");

  const day = await getDayState();
  const timezone = day?.timezone ?? "UTC";
  const today = day?.today ?? "";
  const { isoWeekday } = todayInTimezone(timezone);

  const [{ count: expressCount }, { data: weeklyRaw }, { data: boss }, { data: allHabits }] =
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

  const doneHabitIds = new Set((day?.habits ?? []).filter((h) => h.done).map((h) => h.id));

  const habits: QuestHabit[] = (allHabits ?? []).map((h) => ({
    id: h.id,
    name: h.name,
    stat: h.stat as StatCode,
    difficulty: h.difficulty as "easy" | "medium" | "hard",
    deadline_time: h.deadline_time,
    minimal_version: h.minimal_version,
    active: h.active,
    schedule: (h.schedule ?? { days: [] }) as { days: number[] },
    done: doneHabitIds.has(h.id),
    scheduledToday:
      h.active && ((h.schedule?.days as number[] | undefined) ?? []).includes(isoWeekday),
  }));

  const todos: QuestTodo[] = (day?.todos ?? []).map((t) => ({
    id: t.id,
    title: t.title,
    stat: t.stat,
    difficulty: t.difficulty,
    done: t.done,
  }));

  const weekly: WeeklyQuest[] = (weeklyRaw ?? []).map((q) => ({
    id: q.id,
    stat: (q.definition as { stat: StatCode }).stat,
    progress: q.progress,
    target: q.target,
    reward: rewardLabel(q.reward as Record<string, unknown>),
  }));

  const bossState: BossState =
    boss && today && boss.spawned_on
      ? {
          hp: boss.hp,
          maxHp: boss.max_hp,
          daysLeft: Math.max(
            0,
            14 - Math.floor((Date.parse(today) - Date.parse(boss.spawned_on)) / 86_400_000),
          ),
        }
      : null;

  return (
    <div className="space-y-4">
      <h1 className="px-1 font-display text-xl uppercase tracking-widest text-text-primary">
        Quêtes
      </h1>
      <QuestsView
        habits={habits}
        todos={todos}
        weekly={weekly}
        boss={bossState}
        expressLeft={Math.max(0, 2 - (expressCount ?? 0))}
      />
    </div>
  );
}

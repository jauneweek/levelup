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
  const today = day?.today ?? "";

  const [{ data: weeklyRaw }, { data: boss }] = await Promise.all([
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
  ]);

  // Plus de « programmée aujourd'hui » : sous le quota, une quête est proposée
  // tant que son quota de la période n'est pas rempli. `get_day_state` a déjà
  // tranché côté serveur — le client n'a rien à recalculer.
  const habits: QuestHabit[] = (day?.habits ?? []).map((h) => ({
    id: h.id,
    name: h.name,
    stat: h.stat,
    difficulty: h.difficulty,
    deadline_time: h.deadline_time,
    minimal_version: h.minimal_version,
    recurrence: h.recurrence,
    frequency: h.frequency,
    temporary: h.temporary,
    doneInPeriod: h.doneInPeriod,
    remaining: h.remaining,
    active: true,
    done: h.done,
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
        expressLeft={day?.expressLeft ?? 2}
      />
    </div>
  );
}

import { cache } from "react";
import { createClient } from "@/lib/supabase/server";
import { todayInTimezone } from "@/lib/date";
import type { StatCode } from "@/lib/xp";

export type Difficulty = "easy" | "medium" | "hard";

export type HabitQuest = {
  id: string;
  name: string;
  stat: StatCode;
  difficulty: Difficulty;
  deadline_time: string | null;
  minimal_version: string | null;
  done: boolean;
};

export type TodoQuest = {
  id: string;
  title: string;
  stat: StatCode;
  difficulty: Difficulty;
  done: boolean;
};

export type DayState = {
  userId: string;
  timezone: string;
  today: string;
  habits: HabitQuest[];
  todos: TodoQuest[];
  pendingCount: number;
};

/**
 * État des quêtes du jour (habitudes programmées + todos), avec le drapeau
 * "complétée". Partagé entre le layout (badge de la tab bar), le Hub
 * (prochaine quête) et l'écran Quêtes. `cache` déduplique les requêtes sur
 * un même rendu serveur, donc appeler ce helper 2× dans une requête ne coûte
 * qu'un seul aller-retour Supabase.
 */
export const getDayState = cache(async (): Promise<DayState | null> => {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null;

  const { data: profile } = await supabase
    .from("profiles")
    .select("timezone")
    .eq("id", user.id)
    .maybeSingle();

  const timezone = profile?.timezone ?? "UTC";
  const { dateStr: today, isoWeekday } = todayInTimezone(timezone);

  const { data: habitsRaw } = await supabase
    .from("habits")
    .select("id, name, stat, difficulty, deadline_time, minimal_version, schedule")
    .eq("active", true)
    .order("deadline_time", { ascending: true, nullsFirst: false });

  const scheduled = (habitsRaw ?? []).filter((h) =>
    (h.schedule?.days as number[] | undefined)?.includes(isoWeekday),
  );

  const { data: logs } =
    scheduled.length > 0
      ? await supabase
          .from("habit_logs")
          .select("habit_id")
          .eq("date", today)
          .in(
            "habit_id",
            scheduled.map((h) => h.id),
          )
      : { data: [] as { habit_id: string }[] };
  const doneHabitIds = new Set((logs ?? []).map((l) => l.habit_id));

  const { data: todosRaw } = await supabase
    .from("todos")
    .select("id, title, stat, difficulty, completed_at")
    .eq("date", today)
    .order("created_at", { ascending: true });

  const habits: HabitQuest[] = scheduled.map((h) => ({
    id: h.id,
    name: h.name,
    stat: h.stat as StatCode,
    difficulty: h.difficulty as Difficulty,
    deadline_time: h.deadline_time,
    minimal_version: h.minimal_version,
    done: doneHabitIds.has(h.id),
  }));

  const todos: TodoQuest[] = (todosRaw ?? []).map((t) => ({
    id: t.id,
    title: t.title,
    stat: t.stat as StatCode,
    difficulty: t.difficulty as Difficulty,
    done: t.completed_at !== null,
  }));

  const pendingCount =
    habits.filter((h) => !h.done).length + todos.filter((t) => !t.done).length;

  return { userId: user.id, timezone, today, habits, todos, pendingCount };
});

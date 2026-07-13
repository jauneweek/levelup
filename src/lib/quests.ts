import { cache } from "react";
import { createClient } from "@/lib/supabase/server";
import { getSessionUser } from "@/lib/auth";
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
 *
 * Les requêtes étaient auparavant enchaînées en SÉRIE (auth → profil →
 * habitudes → logs → todos), soit 5 allers-retours bout à bout. Il n'y a en
 * réalité que 2 vraies dépendances : les logs ont besoin des ids d'habitudes,
 * et logs + todos ont besoin de la date locale (donc du fuseau du profil). On
 * regroupe donc en 2 vagues parallèles derrière l'auth.
 */
export const getDayState = cache(async (): Promise<DayState | null> => {
  const user = await getSessionUser();
  if (!user) return null;

  const supabase = await createClient();

  // Vague 1 — profil et habitudes ne dépendent pas l'un de l'autre.
  const [{ data: profile }, { data: habitsRaw }] = await Promise.all([
    supabase
      .from("profiles")
      .select("timezone")
      .eq("id", user.id)
      .maybeSingle(),
    supabase
      .from("habits")
      .select(
        "id, name, stat, difficulty, deadline_time, minimal_version, schedule",
      )
      .eq("active", true)
      .order("deadline_time", { ascending: true, nullsFirst: false }),
  ]);

  const timezone = profile?.timezone ?? "UTC";
  const { dateStr: today, isoWeekday } = todayInTimezone(timezone);

  const scheduled = (habitsRaw ?? []).filter((h) =>
    (h.schedule?.days as number[] | undefined)?.includes(isoWeekday),
  );

  // Vague 2 — logs et todos ont tous deux besoin de `today`, mais pas l'un de
  // l'autre.
  const [logsRes, todosRes] = await Promise.all([
    scheduled.length > 0
      ? supabase
          .from("habit_logs")
          .select("habit_id")
          .eq("date", today)
          .in(
            "habit_id",
            scheduled.map((h) => h.id),
          )
      : Promise.resolve({ data: [] as { habit_id: string }[] }),
    supabase
      .from("todos")
      .select("id, title, stat, difficulty, completed_at")
      .eq("date", today)
      .order("created_at", { ascending: true }),
  ]);

  const doneHabitIds = new Set((logsRes.data ?? []).map((l) => l.habit_id));
  const todosRaw = todosRes.data;

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

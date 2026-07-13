import { cache } from "react";
import { createClient } from "@/lib/supabase/server";
import { getSessionUser } from "@/lib/auth";
import type { Recurrence } from "@/lib/recurrence";
import type { StatCode } from "@/lib/xp";

export type Difficulty = "easy" | "medium" | "hard";

export type { Recurrence } from "@/lib/recurrence";

export type HabitQuest = {
  id: string;
  name: string;
  stat: StatCode;
  difficulty: Difficulty;
  deadline_time: string | null;
  minimal_version: string | null;
  recurrence: Recurrence;
  /** Quota : nombre de fois par période (1 à 10). */
  frequency: number;
  temporary: boolean;
  /** Complétions déjà faites dans la période courante. */
  doneInPeriod: number;
  /** Complétions encore possibles. 0 = quota rempli. */
  remaining: number;
  /** Raccourci : le quota de la période est rempli. */
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
  /** Actions restantes aujourd'hui (un quota ×3 à moitié fait en vaut 2). */
  pendingCount: number;
  /** Dû du jour (§3.5.3) : quotas JOURNALIERS + todos. 0 = journée neutre. */
  dailyDue: number;
  dailyDone: number;
  expressLeft: number;
};

type RawHabit = {
  id: string;
  name: string;
  stat: StatCode;
  difficulty: Difficulty;
  deadline_time: string | null;
  minimal_version: string | null;
  recurrence: Recurrence;
  frequency: number;
  temporary: boolean;
  done_in_period: number;
  remaining: number;
};

type RawDayState = {
  today: string;
  timezone: string;
  express_left: number;
  daily_due: number;
  daily_done: number;
  pending_count: number;
  habits: RawHabit[];
  todos: (Omit<TodoQuest, "done"> & { done: boolean })[];
};

/**
 * État des quêtes du jour.
 *
 * Un seul RPC, et ce n'est pas qu'une optimisation : savoir si le quota de la
 * période courante est rempli suppose de connaître les bornes de la période et
 * d'y sommer les complétions — c'est de la règle de jeu. Elle reste donc côté
 * serveur (`get_day_state`), le client se contente d'afficher. Bénéfice au
 * passage : 1 aller-retour Supabase au lieu de 5.
 */
export const getDayState = cache(async (): Promise<DayState | null> => {
  const user = await getSessionUser();
  if (!user) return null;

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("get_day_state");
  if (error || !data) return null;

  const raw = data as RawDayState;

  return {
    userId: user.id,
    timezone: raw.timezone,
    today: raw.today,
    pendingCount: raw.pending_count,
    dailyDue: raw.daily_due,
    dailyDone: raw.daily_done,
    expressLeft: raw.express_left,
    habits: (raw.habits ?? []).map((h) => ({
      id: h.id,
      name: h.name,
      stat: h.stat,
      difficulty: h.difficulty,
      deadline_time: h.deadline_time,
      minimal_version: h.minimal_version,
      recurrence: h.recurrence,
      frequency: h.frequency,
      temporary: h.temporary,
      doneInPeriod: h.done_in_period,
      remaining: h.remaining,
      done: h.remaining === 0,
    })),
    todos: (raw.todos ?? []).map((t) => ({
      id: t.id,
      title: t.title,
      stat: t.stat,
      difficulty: t.difficulty,
      done: t.done,
    })),
  };
});

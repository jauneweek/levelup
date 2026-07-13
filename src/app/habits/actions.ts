"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { parseCompleteResult, type CompleteResult } from "@/lib/complete-result";
import type { StatCode } from "@/lib/xp";

type Difficulty = "easy" | "medium" | "hard";

function parseDays(formData: FormData): number[] {
  return formData
    .getAll("days")
    .map((d) => Number(d))
    .filter((d) => d >= 1 && d <= 7);
}

export async function createHabit(formData: FormData) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) throw new Error("not authenticated");

  const name = String(formData.get("name") ?? "").trim();
  const stat = String(formData.get("stat") ?? "FOR") as StatCode;
  const difficulty = String(formData.get("difficulty") ?? "easy") as Difficulty;
  const deadlineRaw = String(formData.get("deadline_time") ?? "").trim();
  const minimalVersion = String(formData.get("minimal_version") ?? "").trim();
  const days = parseDays(formData);

  if (!name) throw new Error("le nom de la quête est requis");

  const { error } = await supabase.from("habits").insert({
    user_id: user.id,
    name,
    stat,
    difficulty,
    deadline_time: deadlineRaw || null,
    minimal_version: minimalVersion || null,
    schedule: { days: days.length > 0 ? days : [1, 2, 3, 4, 5, 6, 7] },
  });
  if (error) throw new Error(error.message);

  revalidatePath("/habits");
  revalidatePath("/");
}

export async function updateHabit(formData: FormData) {
  const supabase = await createClient();
  const habitId = String(formData.get("habit_id") ?? "");
  if (!habitId) throw new Error("habit_id manquant");

  const name = String(formData.get("name") ?? "").trim();
  const stat = String(formData.get("stat") ?? "FOR") as StatCode;
  const difficulty = String(formData.get("difficulty") ?? "easy") as Difficulty;
  const deadlineRaw = String(formData.get("deadline_time") ?? "").trim();
  const minimalVersion = String(formData.get("minimal_version") ?? "").trim();
  const days = parseDays(formData);

  if (!name) throw new Error("le nom de la quête est requis");

  const { error } = await supabase
    .from("habits")
    .update({
      name,
      stat,
      difficulty,
      deadline_time: deadlineRaw || null,
      minimal_version: minimalVersion || null,
      schedule: { days: days.length > 0 ? days : [1, 2, 3, 4, 5, 6, 7] },
    })
    .eq("id", habitId);
  if (error) throw new Error(error.message);

  revalidatePath("/habits");
  revalidatePath("/");
}

export async function toggleHabitActive(formData: FormData) {
  const supabase = await createClient();
  const habitId = String(formData.get("habit_id") ?? "");
  const nextActive = formData.get("next_active") === "true";
  if (!habitId) throw new Error("habit_id manquant");

  const { error } = await supabase
    .from("habits")
    .update({ active: nextActive })
    .eq("id", habitId);
  if (error) throw new Error(error.message);

  revalidatePath("/habits");
  revalidatePath("/");
}

export async function deleteHabit(formData: FormData) {
  const supabase = await createClient();
  const habitId = String(formData.get("habit_id") ?? "");
  if (!habitId) throw new Error("habit_id manquant");

  const { error } = await supabase.from("habits").delete().eq("id", habitId);
  if (error) throw new Error(error.message);

  revalidatePath("/habits");
  revalidatePath("/");
}

export async function completeHabit(
  formData: FormData,
): Promise<CompleteResult | null> {
  const supabase = await createClient();
  const habitId = String(formData.get("habit_id") ?? "");
  if (!habitId) throw new Error("habit_id manquant");

  const { data, error } = await supabase.rpc("complete_habit", {
    p_habit_id: habitId,
  });
  if (error) throw new Error(error.message);

  revalidatePath("/");
  return parseCompleteResult(data);
}

export async function completeHabitExpress(
  formData: FormData,
): Promise<CompleteResult | null> {
  const supabase = await createClient();
  const habitId = String(formData.get("habit_id") ?? "");
  if (!habitId) throw new Error("habit_id manquant");

  const { data, error } = await supabase.rpc("complete_habit_express", {
    p_habit_id: habitId,
  });
  if (error) throw new Error(error.message);

  revalidatePath("/");
  return parseCompleteResult(data);
}

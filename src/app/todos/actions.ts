"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { parseCompleteResult, type CompleteResult } from "@/lib/complete-result";
import type { StatCode } from "@/lib/xp";

type Difficulty = "easy" | "medium" | "hard";

export async function createTodo(formData: FormData) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) throw new Error("not authenticated");

  const title = String(formData.get("title") ?? "").trim();
  const stat = String(formData.get("stat") ?? "PRO") as StatCode;
  const difficulty = String(formData.get("difficulty") ?? "easy") as Difficulty;
  const date = String(formData.get("date") ?? "").trim();

  if (!title) throw new Error("le titre est requis");
  if (!date) throw new Error("la date est requise");

  const { error } = await supabase.from("todos").insert({
    user_id: user.id,
    title,
    stat,
    difficulty,
    date,
  });
  if (error) throw new Error(error.message);

  revalidatePath("/");
}

export async function completeTodo(
  formData: FormData,
): Promise<CompleteResult | null> {
  const supabase = await createClient();
  const todoId = String(formData.get("todo_id") ?? "");
  if (!todoId) throw new Error("todo_id manquant");

  const { data, error } = await supabase.rpc("complete_todo", {
    p_todo_id: todoId,
  });
  if (error) throw new Error(error.message);

  revalidatePath("/");
  return parseCompleteResult(data);
}

export async function deleteTodo(formData: FormData) {
  const supabase = await createClient();
  const todoId = String(formData.get("todo_id") ?? "");
  if (!todoId) throw new Error("todo_id manquant");

  const { error } = await supabase.from("todos").delete().eq("id", todoId);
  if (error) throw new Error(error.message);

  revalidatePath("/");
}

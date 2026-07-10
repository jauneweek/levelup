import Link from "next/link";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { SystemWindow } from "@/components/system-window";
import { HabitRow } from "./habit-row";
import { NewHabitForm } from "./new-habit-form";

export default async function HabitsPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect("/login");

  const { data: habits } = await supabase
    .from("habits")
    .select("id, name, stat, difficulty, deadline_time, active, schedule")
    .order("created_at", { ascending: true });

  return (
    <main className="flex-1 p-6">
      <div className="mx-auto max-w-2xl space-y-6">
        <Link href="/" className="text-xs text-cyan hover:underline">
          ← Retour au Hub
        </Link>

        <SystemWindow title="Nouvelle quête">
          <NewHabitForm />
        </SystemWindow>

        <SystemWindow title="Tes quêtes" showSystemTag={false}>
          {!habits || habits.length === 0 ? (
            <p className="text-sm text-text-muted">
              Aucune quête pour l&apos;instant. Crée ta première ci-dessus.
            </p>
          ) : (
            <div className="space-y-3">
              {habits.map((h) => (
                <HabitRow key={h.id} habit={h} />
              ))}
            </div>
          )}
        </SystemWindow>
      </div>
    </main>
  );
}

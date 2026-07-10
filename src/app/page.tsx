import Link from "next/link";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { SystemWindow } from "@/components/system-window";
import { StatBar } from "@/components/stat-bar";
import { HexChip } from "@/components/hex-chip";
import { STAT_LABELS, DIFFICULTY_XP, type StatCode } from "@/lib/xp";
import { todayInTimezone } from "@/lib/date";
import { completeHabit } from "./habits/actions";

const STAT_ORDER: StatCode[] = ["FOR", "INT", "SAG", "PRO", "END"];

export default async function Home() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/login");
  }

  const [{ data: profile }, { data: stats }, { data: habits }] = await Promise.all([
    supabase
      .from("profiles")
      .select("username, rank, global_level, timezone")
      .eq("id", user.id)
      .maybeSingle(),
    supabase
      .from("user_stats")
      .select("stat, level, current_xp")
      .eq("user_id", user.id),
    supabase
      .from("habits")
      .select("id, name, stat, difficulty, deadline_time, schedule")
      .eq("active", true),
  ]);

  const timezone = profile?.timezone ?? "UTC";
  const { dateStr: today, isoWeekday } = todayInTimezone(timezone);

  const todaysHabits = (habits ?? []).filter((h) =>
    (h.schedule?.days as number[] | undefined)?.includes(isoWeekday),
  );

  const { data: logsToday } =
    todaysHabits.length > 0
      ? await supabase
          .from("habit_logs")
          .select("habit_id")
          .eq("date", today)
          .in(
            "habit_id",
            todaysHabits.map((h) => h.id),
          )
      : { data: [] as { habit_id: string }[] };

  const { data: globalStreak } = await supabase
    .from("streaks")
    .select("current, best")
    .is("habit_id", null)
    .maybeSingle();

  const doneIds = new Set((logsToday ?? []).map((l) => l.habit_id));
  const pending = todaysHabits.filter((h) => !doneIds.has(h.id));
  const done = todaysHabits.filter((h) => doneIds.has(h.id));

  const statsByCode = new Map((stats ?? []).map((s) => [s.stat as StatCode, s]));

  return (
    <main className="flex-1 p-6">
      <div className="mx-auto max-w-2xl space-y-6">
        <SystemWindow title="Hub du Chasseur">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-text-muted">
                {profile?.username ?? user.email}
              </p>
              <p className="mt-1 font-display text-2xl text-text-primary">
                Niveau {profile?.global_level ?? 1}
              </p>
            </div>
            <HexChip tone="violet" className="text-base">
              Rang {profile?.rank ?? "E"}
            </HexChip>
          </div>

          <div className="mt-4 flex items-center gap-2 text-xs text-text-muted">
            <span className="text-amber">🔥</span>
            Streak global : {globalStreak?.current ?? 0} j (record{" "}
            {globalStreak?.best ?? 0} j)
          </div>

          <div className="mt-6 space-y-3">
            {STAT_ORDER.map((code) => {
              const s = statsByCode.get(code);
              return (
                <StatBar
                  key={code}
                  stat={code}
                  level={s?.level ?? 1}
                  currentXp={s?.current_xp ?? 0}
                />
              );
            })}
          </div>
        </SystemWindow>

        <SystemWindow title="Quêtes du jour">
          {todaysHabits.length === 0 ? (
            <p className="text-sm text-text-muted">
              Aucune quête programmée aujourd&apos;hui.{" "}
              <Link href="/habits" className="text-cyan hover:underline">
                Créer une quête
              </Link>
              .
            </p>
          ) : (
            <div className="space-y-2">
              {pending.map((h) => (
                <form
                  key={h.id}
                  action={completeHabit}
                  className="flex items-center justify-between gap-3 rounded border border-border-glow p-3"
                >
                  <input type="hidden" name="habit_id" value={h.id} />
                  <div>
                    <p className="text-sm text-text-primary">{h.name}</p>
                    <p className="text-xs text-text-muted">
                      {STAT_LABELS[h.stat as StatCode]}
                      {h.deadline_time
                        ? ` · avant ${h.deadline_time.slice(0, 5)}`
                        : ""}
                    </p>
                  </div>
                  <div className="flex items-center gap-2">
                    <HexChip tone="cyan">+{DIFFICULTY_XP[h.difficulty as "easy" | "medium" | "hard"]} XP</HexChip>
                    <button
                      type="submit"
                      className="rounded bg-violet px-3 py-1.5 text-xs font-medium text-white hover:opacity-90"
                    >
                      Check-in
                    </button>
                  </div>
                </form>
              ))}

              {done.map((h) => (
                <div
                  key={h.id}
                  className="flex items-center justify-between gap-3 rounded border border-border-glow p-3 opacity-50"
                >
                  <p className="text-sm text-text-primary line-through">
                    {h.name}
                  </p>
                  <span className="text-xs text-cyan">✓ complétée</span>
                </div>
              ))}
            </div>
          )}

          <Link
            href="/habits"
            className="mt-4 inline-block text-xs text-cyan hover:underline"
          >
            Gérer mes quêtes →
          </Link>
        </SystemWindow>

        <form action="/auth/signout" method="post">
          <button
            type="submit"
            className="w-full rounded border border-border-glow bg-transparent px-4 py-2 text-sm text-text-muted transition-colors hover:border-danger hover:text-danger"
          >
            Se déconnecter
          </button>
        </form>
      </div>
    </main>
  );
}

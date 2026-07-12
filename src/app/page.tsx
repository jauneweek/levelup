import Link from "next/link";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { SystemWindow } from "@/components/system-window";
import { StatBar } from "@/components/stat-bar";
import { HexChip } from "@/components/hex-chip";
import { Blason } from "@/components/blason";
import { TodoQuickAdd } from "@/components/todo-quick-add";
import { STAT_LABELS, DIFFICULTY_XP, type StatCode } from "@/lib/xp";
import { todayInTimezone, tomorrowInTimezone } from "@/lib/date";
import { PushSubscribeButton } from "@/components/push-subscribe-button";
import { completeHabit, completeHabitExpress } from "./habits/actions";
import { completeTodo } from "./todos/actions";

const STAT_ORDER: StatCode[] = ["FOR", "INT", "SAG", "PRO", "END"];

const EVENT_LABELS: Record<string, string> = {
  potion: "🧪 Potion d'Énergie active — XP ×2 si journée parfaite aujourd'hui.",
  chest: "💰 Coffre mystère détecté — s'ouvre à 3 quêtes complétées.",
  rush: "⚡ Heure de rush — une quête tirée au sort vaut XP ×2 avant midi.",
  cursed: "🌑 Jour maudit — les pénalités sont doublées aujourd'hui.",
};

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
      .select("username, rank, global_level, timezone, emblem_damage")
      .eq("id", user.id)
      .maybeSingle(),
    supabase
      .from("user_stats")
      .select("stat, level, current_xp")
      .eq("user_id", user.id),
    supabase
      .from("habits")
      .select("id, name, stat, difficulty, deadline_time, minimal_version, schedule")
      .eq("active", true),
  ]);

  const timezone = profile?.timezone ?? "UTC";
  const { dateStr: today, isoWeekday } = todayInTimezone(timezone);
  const tomorrow = tomorrowInTimezone(timezone);

  const todaysHabits = (habits ?? []).filter((h) =>
    (h.schedule?.days as number[] | undefined)?.includes(isoWeekday),
  );

  const [
    { data: logsToday },
    { data: globalStreak },
    { data: todosToday },
    { data: todosTomorrow },
    { data: eventToday },
    { data: bossActive },
    { data: secretQuestToday },
  ] = await Promise.all([
    todaysHabits.length > 0
      ? supabase
          .from("habit_logs")
          .select("habit_id")
          .eq("date", today)
          .in(
            "habit_id",
            todaysHabits.map((h) => h.id),
          )
      : Promise.resolve({ data: [] as { habit_id: string }[] }),
    supabase
      .from("streaks")
      .select("current, best")
      .is("habit_id", null)
      .maybeSingle(),
    supabase
      .from("todos")
      .select("id, title, stat, difficulty, completed_at")
      .eq("date", today)
      .order("created_at", { ascending: true }),
    supabase
      .from("todos")
      .select("id, title, stat, difficulty")
      .eq("date", tomorrow)
      .order("created_at", { ascending: true }),
    supabase
      .from("events_log")
      .select("event_type")
      .eq("date", today)
      .maybeSingle(),
    supabase
      .from("boss_fights")
      .select("hp, max_hp")
      .eq("status", "active")
      .maybeSingle(),
    supabase
      .from("secret_quests")
      .select("revealed")
      .eq("date", today)
      .maybeSingle(),
  ]);

  const doneIds = new Set((logsToday ?? []).map((l) => l.habit_id));
  const pendingHabits = todaysHabits.filter((h) => !doneIds.has(h.id));
  const doneHabits = todaysHabits.filter((h) => doneIds.has(h.id));

  const pendingTodos = (todosToday ?? []).filter((t) => !t.completed_at);
  const doneTodos = (todosToday ?? []).filter((t) => t.completed_at);

  const statsByCode = new Map((stats ?? []).map((s) => [s.stat as StatCode, s]));
  const noQuestsToday = todaysHabits.length === 0 && (todosToday ?? []).length === 0;

  const eventLabel = eventToday?.event_type ? EVENT_LABELS[eventToday.event_type] : undefined;

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
            <div className="flex items-center gap-3">
              <Blason emblemDamage={profile?.emblem_damage ?? 0} />
              <HexChip tone="violet" className="text-base">
                Rang {profile?.rank ?? "E"}
              </HexChip>
            </div>
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

        <SystemWindow title="Brief du matin">
          <ul className="space-y-1.5 text-sm text-text-muted">
            <li>
              🗓️ {todaysHabits.length + (todosToday?.length ?? 0)} quête(s) chargée(s)
              aujourd&apos;hui.
            </li>
            {eventLabel && <li className="text-amber">{eventLabel}</li>}
            {bossActive && (
              <li className="text-danger">
                👹 Boss de la Procrastination actif — {bossActive.hp}/{bossActive.max_hp} PV.
              </li>
            )}
            {secretQuestToday && !secretQuestToday.revealed && (
              <li className="text-cyan">
                🎁 Une quête du jour cache un trésor. Il ne se révèle qu&apos;à la
                complétion.
              </li>
            )}
          </ul>
        </SystemWindow>

        <SystemWindow title="Quêtes du jour">
          {noQuestsToday ? (
            <p className="text-sm text-text-muted">
              Aucune quête programmée aujourd&apos;hui.{" "}
              <Link href="/habits" className="text-cyan hover:underline">
                Créer une quête
              </Link>
              .
            </p>
          ) : (
            <div className="space-y-2">
              {pendingHabits.map((h) => (
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
                    {h.minimal_version && (
                      <button
                        type="submit"
                        formAction={completeHabitExpress}
                        title={`Version express : ${h.minimal_version}`}
                        className="rounded border border-amber/60 px-2 py-1.5 text-xs text-amber hover:bg-amber/10"
                      >
                        ⚡ Express
                      </button>
                    )}
                    <button
                      type="submit"
                      className="rounded bg-violet px-3 py-1.5 text-xs font-medium text-white hover:opacity-90"
                    >
                      Check-in
                    </button>
                  </div>
                </form>
              ))}

              {pendingTodos.map((t) => (
                <form
                  key={t.id}
                  action={completeTodo}
                  className="flex items-center justify-between gap-3 rounded border border-border-glow p-3"
                >
                  <input type="hidden" name="todo_id" value={t.id} />
                  <div>
                    <p className="text-sm text-text-primary">📋 {t.title}</p>
                    <p className="text-xs text-text-muted">
                      {STAT_LABELS[t.stat as StatCode]} · todo
                    </p>
                  </div>
                  <div className="flex items-center gap-2">
                    <HexChip tone="cyan">+{DIFFICULTY_XP[t.difficulty as "easy" | "medium" | "hard"]} XP</HexChip>
                    <button
                      type="submit"
                      className="rounded bg-violet px-3 py-1.5 text-xs font-medium text-white hover:opacity-90"
                    >
                      Check-in
                    </button>
                  </div>
                </form>
              ))}

              {doneHabits.map((h) => (
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

              {doneTodos.map((t) => (
                <div
                  key={t.id}
                  className="flex items-center justify-between gap-3 rounded border border-border-glow p-3 opacity-50"
                >
                  <p className="text-sm text-text-primary line-through">
                    📋 {t.title}
                  </p>
                  <span className="text-xs text-cyan">✓ complétée</span>
                </div>
              ))}
            </div>
          )}

          <div className="mt-4 flex gap-4">
            <Link href="/habits" className="text-xs text-cyan hover:underline">
              Gérer mes quêtes →
            </Link>
            <Link href="/profil" className="text-xs text-cyan hover:underline">
              Profil (Ombres, Fantôme, Journal) →
            </Link>
          </div>
        </SystemWindow>

        <SystemWindow title="Planifier demain" showSystemTag={false}>
          <p className="mb-3 text-xs text-text-muted">
            Prépare une todo pour demain ce soir : l&apos;acte de planifier
            rapporte +10 XP Productivité (une fois par jour).
          </p>
          <TodoQuickAdd date={tomorrow} />

          {todosTomorrow && todosTomorrow.length > 0 && (
            <div className="mt-4 space-y-1.5">
              {todosTomorrow.map((t) => (
                <div
                  key={t.id}
                  className="flex items-center justify-between rounded border border-border-glow p-2 text-xs"
                >
                  <span className="text-text-primary">📋 {t.title}</span>
                  <span className="text-text-muted">{STAT_LABELS[t.stat as StatCode]}</span>
                </div>
              ))}
            </div>
          )}
        </SystemWindow>

        <SystemWindow title="Rappels du Système" showSystemTag={false}>
          <p className="mb-3 text-xs text-text-muted">
            Reçois un rappel [SYSTÈME] avant l&apos;heure limite de tes
            quêtes (T-30, T-15).
          </p>
          <PushSubscribeButton />
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

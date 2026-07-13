import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { SystemWindow } from "@/components/system-window";
import { StatBar } from "@/components/stat-bar";
import { StatRadar } from "@/components/stat-radar";
import { RankBadge } from "@/components/rank-badge";
import { Blason } from "@/components/blason";
import { QuestCard } from "@/components/quest-card";
import { DIFFICULTY_XP, xpToNextLevel, type StatCode } from "@/lib/xp";
import { getDayState } from "@/lib/quests";

const STAT_ORDER: StatCode[] = ["FOR", "INT", "SAG", "PRO", "END"];
type HunterRank = "E" | "D" | "C" | "B" | "A" | "S";

const EVENT_LABELS: Record<string, string> = {
  potion: "🧪 Potion d'Énergie active — XP ×2 si journée parfaite aujourd'hui.",
  chest: "💰 Coffre mystère détecté — s'ouvre à 3 quêtes complétées.",
  rush: "⚡ Heure de rush — une quête tirée au sort vaut XP ×2 avant midi.",
  cursed: "🌑 Jour maudit — les pénalités sont doublées aujourd'hui.",
};

/** Score global = total d'XP cumulée sur les 5 stats (mockup « SCORE GLOBAL »). */
function cumulativeXp(level: number, currentXp: number): number {
  let total = currentXp;
  for (let k = 1; k < level; k++) total += xpToNextLevel(k);
  return total;
}

export default async function HubPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect("/login");

  const day = await getDayState();

  const [
    { data: profile },
    { data: stats },
    { data: globalStreak },
    { data: eventToday },
    { data: bossActive },
    { data: secretQuestToday },
  ] = await Promise.all([
    supabase
      .from("profiles")
      .select("username, rank, global_level, emblem_damage")
      .eq("id", user.id)
      .maybeSingle(),
    supabase.from("user_stats").select("stat, level, current_xp").eq("user_id", user.id),
    supabase.from("streaks").select("current, best, shields").is("habit_id", null).maybeSingle(),
    supabase.from("events_log").select("event_type").eq("date", day?.today ?? "").maybeSingle(),
    supabase.from("boss_fights").select("hp, max_hp").eq("status", "active").maybeSingle(),
    supabase.from("secret_quests").select("revealed").eq("date", day?.today ?? "").maybeSingle(),
  ]);

  const statsByCode = new Map((stats ?? []).map((s) => [s.stat as StatCode, s]));
  const levels = Object.fromEntries(
    STAT_ORDER.map((c) => [c, statsByCode.get(c)?.level ?? 1]),
  ) as Record<StatCode, number>;

  const rank = (profile?.rank ?? "E") as HunterRank;
  const globalLevel = profile?.global_level ?? 1;

  // Progression globale = moyenne des remplissages d'XP par stat.
  const aggPct = Math.round(
    (STAT_ORDER.reduce((sum, c) => {
      const s = statsByCode.get(c);
      return sum + (s ? (s.current_xp ?? 0) / xpToNextLevel(s.level ?? 1) : 0);
    }, 0) /
      STAT_ORDER.length) *
      100,
  );
  const score = STAT_ORDER.reduce((sum, c) => {
    const s = statsByCode.get(c);
    return sum + cumulativeXp(s?.level ?? 1, s?.current_xp ?? 0);
  }, 0);

  const eventLabel = eventToday?.event_type ? EVENT_LABELS[eventToday.event_type] : undefined;

  const pendingHabits = (day?.habits ?? []).filter((h) => !h.done);
  const pendingTodos = (day?.todos ?? []).filter((t) => !t.done);
  const nextHabit = pendingHabits[0];
  const nextTodo = !nextHabit ? pendingTodos[0] : undefined;
  const remaining = pendingHabits.length + pendingTodos.length;

  return (
    <div className="relative space-y-5">
      <div className="app-nebula" aria-hidden />

      {/* ── Hero : rang + niveau + progression ── */}
      <SystemWindow title="Hub du Chasseur">
        <div className="flex flex-col items-center pt-2 text-center">
          <div className="rank-halo">
            <div className="rank-shards" aria-hidden>
              <span style={{ top: "6%", left: "12%" }} />
              <span style={{ top: "14%", right: "8%" }} />
              <span style={{ bottom: "18%", left: "6%" }} />
              <span style={{ bottom: "8%", right: "16%" }} />
            </div>
            <RankBadge rank={rank} size={104} />
          </div>
          <p className="mt-3 font-display text-xs tracking-[0.35em] text-violet">
            RANG {rank} · CHASSEUR
          </p>
          <p className="font-display text-4xl leading-none text-text-primary">
            NIVEAU {globalLevel}
          </p>
          <p className="mt-1 text-xs text-text-muted">{profile?.username ?? user.email}</p>
        </div>

        <div className="mt-5">
          <div className="mb-1.5 flex items-baseline justify-between text-xs">
            <span className="uppercase tracking-widest text-text-muted">Progression</span>
            <span className="font-display tabular-nums text-cyan">{aggPct}%</span>
          </div>
          <div className="xp-track">
            <div className="xp-fill" style={{ width: `${aggPct}%` }} />
          </div>
          <p className="mt-2.5 text-center text-xs text-text-muted">
            Score global :{" "}
            <b className="font-display tabular-nums text-cyan">{score.toLocaleString("fr-FR")}</b>
          </p>
        </div>
      </SystemWindow>

      {/* ── Série (flamme) + blason ── */}
      <SystemWindow title="Série" showSystemTag={false} tone="amber">
        <div className="flex items-center gap-4">
          <div className="flame shrink-0">
            <span className="flame__glyph" aria-hidden>
              🔥
            </span>
            <span className="flame__num tabular-nums">{globalStreak?.current ?? 0}</span>
          </div>
          <div className="flex-1">
            <p className="font-display text-lg uppercase tracking-wider text-text-primary">
              Jours de série
            </p>
            <p className="mt-0.5 text-xs text-amber">
              Record : {globalStreak?.best ?? 0} · 🛡️ {globalStreak?.shields ?? 0} bouclier
              {(globalStreak?.shields ?? 0) > 1 ? "s" : ""}
            </p>
          </div>
          <Blason emblemDamage={profile?.emblem_damage ?? 0} />
        </div>
      </SystemWindow>

      {/* ── Radar des stats + détail ── */}
      <SystemWindow title="Statistiques" showSystemTag={false} tone="cyan">
        <div className="flex flex-col items-center">
          <StatRadar levels={levels} size={268} />
        </div>
        <div className="mt-4 space-y-2.5">
          {STAT_ORDER.map((code) => {
            const s = statsByCode.get(code);
            return (
              <StatBar key={code} stat={code} level={s?.level ?? 1} currentXp={s?.current_xp ?? 0} />
            );
          })}
        </div>
      </SystemWindow>

      {/* ── Prochaine quête ── */}
      <SystemWindow title="Prochaine quête" showSystemTag={false}>
        {nextHabit ? (
          <QuestCard
            id={nextHabit.id}
            kind="habit"
            name={nextHabit.name}
            stat={nextHabit.stat}
            xp={DIFFICULTY_XP[nextHabit.difficulty]}
            done={false}
            meta={
              nextHabit.deadline_time
                ? `avant ${nextHabit.deadline_time.slice(0, 5)}`
                : `${remaining} restante${remaining > 1 ? "s" : ""} aujourd'hui`
            }
            express={nextHabit.minimal_version}
          />
        ) : nextTodo ? (
          <QuestCard
            id={nextTodo.id}
            kind="todo"
            name={nextTodo.title}
            stat={nextTodo.stat}
            xp={DIFFICULTY_XP[nextTodo.difficulty]}
            done={false}
            meta="todo"
          />
        ) : (
          <p className="text-sm text-text-muted">
            Toutes tes quêtes du jour sont complétées. Journée parfaite en vue. ✦
          </p>
        )}
      </SystemWindow>

      {/* ── Flavor du jour ── */}
      {(eventLabel || bossActive || (secretQuestToday && !secretQuestToday.revealed)) && (
        <SystemWindow
          title="Le donjon du jour"
          showSystemTag={false}
          tone={bossActive ? "danger" : "amber"}
        >
          <ul className="space-y-2 text-sm">
            {eventLabel && <li className="text-amber">{eventLabel}</li>}
            {bossActive && (
              <li className="text-danger">
                👹 Boss de la Procrastination — {bossActive.hp}/{bossActive.max_hp} PV. Chaque
                journée parfaite lui retire 1 PV.
              </li>
            )}
            {secretQuestToday && !secretQuestToday.revealed && (
              <li className="text-cyan">🎁 Une quête du jour cache un trésor.</li>
            )}
          </ul>
        </SystemWindow>
      )}
    </div>
  );
}

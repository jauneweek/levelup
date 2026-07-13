import Link from "next/link";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { SystemWindow } from "@/components/system-window";
import { StatRadar } from "@/components/stat-radar";
import { StatDetailModal, type StatEntry } from "@/components/stat-detail-modal";
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
  const statEntries = Object.fromEntries(
    STAT_ORDER.map((c) => [
      c,
      {
        level: statsByCode.get(c)?.level ?? 1,
        current_xp: statsByCode.get(c)?.current_xp ?? 0,
      } satisfies StatEntry,
    ]),
  ) as Record<StatCode, StatEntry>;

  const rank = (profile?.rank ?? "E") as HunterRank;
  const globalLevel = profile?.global_level ?? 1;

  const aggPct = Math.round(
    (STAT_ORDER.reduce((sum, c) => {
      const s = statEntries[c];
      return sum + s.current_xp / xpToNextLevel(s.level);
    }, 0) /
      STAT_ORDER.length) *
      100,
  );
  const score = STAT_ORDER.reduce(
    (sum, c) => sum + cumulativeXp(statEntries[c].level, statEntries[c].current_xp),
    0,
  );

  const eventLabel = eventToday?.event_type ? EVENT_LABELS[eventToday.event_type] : undefined;

  const pendingHabits = (day?.habits ?? []).filter((h) => !h.done);
  const pendingTodos = (day?.todos ?? []).filter((t) => !t.done);
  const doneHabits = (day?.habits ?? []).filter((h) => h.done);
  const doneTodos = (day?.todos ?? []).filter((t) => t.done);
  const total =
    pendingHabits.length + pendingTodos.length + doneHabits.length + doneTodos.length;
  const doneCount = doneHabits.length + doneTodos.length;

  return (
    <div className="relative space-y-4">
      <div className="app-nebula" aria-hidden />

      {/* ── Identité : rang · niveau · progression · radar ── */}
      <SystemWindow title="Hub du Chasseur">
        <div className="flex flex-col items-center text-center">
          <div className="rank-halo">
            <div className="rank-shards" aria-hidden>
              <span style={{ top: "6%", left: "12%" }} />
              <span style={{ top: "14%", right: "8%" }} />
              <span style={{ bottom: "18%", left: "6%" }} />
              <span style={{ bottom: "8%", right: "16%" }} />
            </div>
            <RankBadge rank={rank} size={72} />
          </div>
          <p className="mt-2 font-display text-2xl leading-none text-text-primary">
            NIVEAU {globalLevel}
          </p>
        </div>

        <div className="mt-3.5">
          <div className="mb-1.5 flex items-baseline justify-between text-[11px]">
            <span className="uppercase tracking-widest text-text-muted">Progression</span>
            <span className="font-display tabular-nums text-cyan">{aggPct}%</span>
          </div>
          <div className="xp-track">
            <div className="xp-fill" style={{ width: `${aggPct}%` }} />
          </div>
        </div>

        {/* Bandeau compact : série · boucliers · blason */}
        <div className="mt-3 flex items-center justify-between text-xs">
          <span className="text-text-muted">
            🔥{" "}
            <b className="font-display tabular-nums text-amber">{globalStreak?.current ?? 0} j</b>
            <span className="text-text-muted/70"> · record {globalStreak?.best ?? 0}</span>
          </span>
          <span className="text-text-muted">
            🛡️ <b className="text-cyan">{globalStreak?.shields ?? 0}</b>
          </span>
          <Blason emblemDamage={profile?.emblem_damage ?? 0} size={28} showLabel={false} />
        </div>

        {/* Radar + accès au détail (les niveaux précis vivent dans le modal
            et dans le Profil — le Hub reste centré sur l'action). */}
        <div className="mt-1 flex flex-col items-center">
          <StatRadar levels={levels} size={172} />
          <div className="mt-0.5 flex w-full items-center justify-between text-[11px]">
            <StatDetailModal stats={statEntries} />
            <span className="text-text-muted">
              Score{" "}
              <b className="font-display tabular-nums text-cyan">
                {score.toLocaleString("fr-FR")}
              </b>
            </span>
          </div>
        </div>
      </SystemWindow>

      {/* ── Quêtes du jour (l'essentiel, sans scroll) ── */}
      <SystemWindow title="Quêtes du jour" showSystemTag={false}>
        {total === 0 ? (
          <p className="text-sm text-text-muted">
            Aucune quête programmée aujourd&apos;hui.{" "}
            <Link href="/quetes" className="text-cyan hover:underline">
              Créer une quête
            </Link>
            .
          </p>
        ) : (
          <>
            <div className="space-y-2">
              {pendingHabits.map((h) => (
                <QuestCard
                  key={h.id}
                  id={h.id}
                  kind="habit"
                  name={h.name}
                  stat={h.stat}
                  xp={DIFFICULTY_XP[h.difficulty]}
                  done={false}
                  meta={h.deadline_time ? `avant ${h.deadline_time.slice(0, 5)}` : undefined}
                  express={h.minimal_version}
                />
              ))}
              {pendingTodos.map((t) => (
                <QuestCard
                  key={t.id}
                  id={t.id}
                  kind="todo"
                  name={t.title}
                  stat={t.stat}
                  xp={DIFFICULTY_XP[t.difficulty]}
                  done={false}
                  meta="todo"
                />
              ))}
              {doneHabits.map((h) => (
                <QuestCard
                  key={h.id}
                  id={h.id}
                  kind="habit"
                  name={h.name}
                  stat={h.stat}
                  xp={DIFFICULTY_XP[h.difficulty]}
                  done
                />
              ))}
              {doneTodos.map((t) => (
                <QuestCard
                  key={t.id}
                  id={t.id}
                  kind="todo"
                  name={t.title}
                  stat={t.stat}
                  xp={DIFFICULTY_XP[t.difficulty]}
                  done
                />
              ))}
            </div>
            <p className="mt-3 text-center text-xs text-text-muted">
              <b className="font-display tabular-nums text-cyan">
                {doneCount}/{total}
              </b>{" "}
              complétées ·{" "}
              <Link href="/quetes" className="text-cyan hover:underline">
                Hebdo &amp; gestion →
              </Link>
            </p>
          </>
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

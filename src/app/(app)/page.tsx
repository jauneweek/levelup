import Link from "next/link";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { SystemWindow } from "@/components/system-window";
import { StatRadar } from "@/components/stat-radar";
import { StatDetailModal, type StatEntry } from "@/components/stat-detail-modal";
import { RankBadge, DAMAGE_LABEL } from "@/components/rank-badge";
import { xpToNextLevel, type StatCode } from "@/lib/xp";
import { getDayState } from "@/lib/quests";
import { buildSystemMessage } from "@/lib/system-message";
import { offsetDateInTimezone } from "@/lib/date";

const STAT_ORDER: StatCode[] = ["FOR", "INT", "SAG", "PRO", "END"];
type HunterRank = "E" | "D" | "C" | "B" | "A" | "S";

/** Score global = total d'XP cumulée sur les 5 stats (mockup « SCORE GLOBAL »). */
function cumulativeXp(level: number, currentXp: number): number {
  let total = currentXp;
  for (let k = 1; k < level; k++) total += xpToNextLevel(k);
  return total;
}

/**
 * Hub — le « sanctuaire ». C'est un MIROIR, pas un tableau de bord : rang,
 * niveau, compétences, blason (qui se fissure), et le message du Système.
 * Aucune liste de quêtes, aucun check-in : l'action vit dans l'onglet Quêtes,
 * et les push T-30/T-15 y atterrissent directement.
 * (Emplacement prévu pour le personnage du Chasseur — plus tard.)
 */
export default async function HubPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect("/login");

  const day = await getDayState();
  const timezone = day?.timezone ?? "UTC";
  const today = day?.today ?? "";
  const ghostDate = offsetDateInTimezone(timezone, -30);

  const [
    { data: profile },
    { data: stats },
    { data: globalStreak },
    { data: boss },
    { data: ghostSnap },
    { data: lastSnap },
  ] = await Promise.all([
    supabase
      .from("profiles")
      .select("username, rank, global_level, emblem_damage, consecutive_abuse_days")
      .eq("id", user.id)
      .maybeSingle(),
    supabase.from("user_stats").select("stat, level, current_xp").eq("user_id", user.id),
    supabase.from("streaks").select("current, best, shields").is("habit_id", null).maybeSingle(),
    supabase
      .from("boss_fights")
      .select("hp, max_hp, spawned_on")
      .eq("status", "active")
      .maybeSingle(),
    supabase.from("daily_snapshots").select("global_level").eq("date", ghostDate).maybeSingle(),
    supabase
      .from("daily_snapshots")
      .select("completion_rate_7d")
      .order("date", { ascending: false })
      .limit(1)
      .maybeSingle(),
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
  const emblemDamage = profile?.emblem_damage ?? 0;

  const aggPct = Math.round(
    (STAT_ORDER.reduce(
      (sum, c) => sum + statEntries[c].current_xp / xpToNextLevel(statEntries[c].level),
      0,
    ) /
      STAT_ORDER.length) *
      100,
  );
  const score = STAT_ORDER.reduce(
    (sum, c) => sum + cumulativeXp(statEntries[c].level, statEntries[c].current_xp),
    0,
  );

  const pending = day?.pendingCount ?? 0;
  const total = (day?.habits.length ?? 0) + (day?.todos.length ?? 0);

  const bossCtx =
    boss && today && boss.spawned_on
      ? {
          hp: boss.hp,
          maxHp: boss.max_hp,
          daysLeft: Math.max(
            0,
            14 - Math.floor((Date.parse(today) - Date.parse(boss.spawned_on)) / 86_400_000),
          ),
        }
      : null;

  const message = buildSystemMessage({
    rank,
    streak: globalStreak?.current ?? 0,
    pending,
    total,
    consecutiveAbuseDays: profile?.consecutive_abuse_days ?? 0,
    boss: bossCtx,
    ghostDelta: ghostSnap ? globalLevel - ghostSnap.global_level : null,
    isSlump: (lastSnap?.completion_rate_7d ?? 1) < 0.4,
  });

  const dmg = Math.max(0, Math.min(3, emblemDamage)) as 0 | 1 | 2 | 3;

  return (
    <div className="relative space-y-4">
      <div className="app-nebula" aria-hidden />

      {/* ── Identité : blason/rang · niveau collé à la barre d'XP ── */}
      <SystemWindow title={undefined}>
        <div className="-mt-4 flex flex-col items-center">
          <div className="rank-halo">
            <div className="rank-shards" aria-hidden>
              <span style={{ top: "6%", left: "12%" }} />
              <span style={{ top: "14%", right: "8%" }} />
              <span style={{ bottom: "18%", left: "6%" }} />
              <span style={{ bottom: "8%", right: "16%" }} />
            </div>
            <RankBadge rank={rank} emblemDamage={emblemDamage} size={96} />
          </div>
          <p className="mt-2 text-[11px] text-text-muted">
            {profile?.username ?? user.email} · {DAMAGE_LABEL[dmg]}
          </p>
        </div>

        {/* Niveau À CÔTÉ de la barre d'XP (mockup) */}
        <div className="mt-4 flex items-center gap-3">
          <span className="font-display shrink-0 text-lg leading-none text-text-primary">
            NIV. {globalLevel}
          </span>
          <div className="xp-track flex-1">
            <div className="xp-fill" style={{ width: `${aggPct}%` }} />
          </div>
          <span className="font-display shrink-0 text-xs tabular-nums text-cyan">{aggPct}%</span>
        </div>

        <div className="mt-2.5 flex items-center justify-between text-xs text-text-muted">
          <span>
            🔥{" "}
            <b className="font-display tabular-nums text-amber">{globalStreak?.current ?? 0} j</b>
            <span className="text-text-muted/70"> · record {globalStreak?.best ?? 0}</span>
          </span>
          <span>
            🛡️ <b className="text-cyan">{globalStreak?.shields ?? 0}</b>
          </span>
          <span>
            Score{" "}
            <b className="font-display tabular-nums text-cyan">{score.toLocaleString("fr-FR")}</b>
          </span>
        </div>
      </SystemWindow>

      {/* ── Compétences : le radar EST la cible, il ouvre le détail ── */}
      <SystemWindow title={undefined} tone="cyan" className="!py-5">
        <div className="-mt-4">
          <StatDetailModal stats={statEntries}>
            <StatRadar levels={levels} />
          </StatDetailModal>
        </div>
      </SystemWindow>

      {/* ── Le miroir : ce que le Système pense de toi ── */}
      <SystemWindow title={undefined} tone={message.tone} className="!py-4">
        <div className="-mt-4">
          <p className="font-display text-[0.7rem] tracking-[0.22em] text-[color:var(--sw-accent)]">
            [SYSTÈME]
          </p>
          <p className="mt-1.5 text-sm leading-relaxed text-text-primary">{message.text}</p>
        </div>
      </SystemWindow>

      {/* ── L'unique action du Hub : entrer dans le donjon ── */}
      {total === 0 ? (
        <Link href="/quetes" className="sys-cta w-full whitespace-nowrap">
          Créer ta première quête
        </Link>
      ) : pending > 0 ? (
        <Link href="/quetes" className="sys-cta w-full whitespace-nowrap">
          Entrer dans le donjon
          <span
            className="clip-hex-wide px-2.5 py-0.5 text-[0.72rem] tabular-nums"
            style={{ background: "rgba(0,0,0,0.28)" }}
          >
            {pending}
          </span>
        </Link>
      ) : (
        <Link href="/quetes" className="sys-cta sys-cta--ghost w-full whitespace-nowrap py-3">
          Journée bouclée
        </Link>
      )}
    </div>
  );
}

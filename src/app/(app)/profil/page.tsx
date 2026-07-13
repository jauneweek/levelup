import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { SystemWindow } from "@/components/system-window";
import { RankBadge } from "@/components/rank-badge";
import { StatBar } from "@/components/stat-bar";
import { ShadowSilhouette, type ShadowGrade } from "@/components/shadow-silhouette";
import { PushSubscribeButton } from "@/components/push-subscribe-button";
import { type StatCode } from "@/lib/xp";
import { offsetDateInTimezone } from "@/lib/date";

const STAT_ORDER: StatCode[] = ["FOR", "INT", "SAG", "PRO", "END"];
type HunterRank = "E" | "D" | "C" | "B" | "A" | "S";

export default async function ProfilPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect("/login");

  const { data: profile } = await supabase
    .from("profiles")
    .select("username, rank, global_level, timezone")
    .eq("id", user.id)
    .maybeSingle();

  const timezone = profile?.timezone ?? "UTC";
  const ghostDate = offsetDateInTimezone(timezone, -30);

  const [
    { data: stats },
    { data: ghostSnapshot },
    { data: shadows },
    { data: journalEntries },
    { data: userTitles },
    { data: userItems },
  ] = await Promise.all([
    supabase.from("user_stats").select("stat, level, current_xp").eq("user_id", user.id),
    supabase
      .from("daily_snapshots")
      .select("global_level, stats")
      .eq("date", ghostDate)
      .maybeSingle(),
    supabase
      .from("shadows")
      .select("id, name, grade, extracted_at")
      .order("extracted_at", { ascending: false }),
    supabase
      .from("journal_entries")
      .select("week_start, payload")
      .order("week_start", { ascending: false }),
    supabase
      .from("user_titles")
      .select("equipped, unlocked_at, titles(name)")
      .order("unlocked_at", { ascending: false }),
    supabase.from("user_items").select("quantity, items(name, rarity)"),
  ]);

  const statsByCode = new Map((stats ?? []).map((s) => [s.stat as StatCode, s]));
  const ghostStats = (ghostSnapshot?.stats ?? {}) as Record<
    string,
    { level: number; current_xp: number }
  >;
  const globalLevel = profile?.global_level ?? 1;
  const rank = (profile?.rank ?? "E") as HunterRank;
  const ghostGlobalLevel = ghostSnapshot?.global_level ?? null;
  const globalDelta = ghostGlobalLevel !== null ? globalLevel - ghostGlobalLevel : null;

  const titles = (userTitles ?? []).map((t) => ({
    name: (t.titles as unknown as { name: string } | null)?.name ?? "",
    equipped: t.equipped,
  }));
  const equippedTitle = titles.find((t) => t.equipped)?.name ?? titles[0]?.name ?? null;
  const itemCount = (userItems ?? []).reduce((sum, i) => sum + (i.quantity ?? 0), 0);

  return (
    <div className="space-y-5">
      <div className="flex items-baseline justify-between px-1">
        <h1 className="font-display text-xl uppercase tracking-widest text-text-primary">Profil</h1>
        <span className="font-display text-xs tracking-[0.3em] text-violet">[SYSTÈME]</span>
      </div>

      {/* ── Hero ── */}
      <SystemWindow title="Profil du Chasseur">
        <div className="flex items-center gap-4">
          <RankBadge rank={rank} size={72} />
          <div className="min-w-0 flex-1">
            <p className="truncate font-display text-lg leading-tight text-text-primary">
              {profile?.username ?? user.email}
            </p>
            <p className="mt-0.5 text-xs text-text-muted">
              Rang {rank} · Niveau {globalLevel}
            </p>
          </div>
        </div>
        {equippedTitle && (
          <div className="mt-4 flex justify-center">
            <span className="clip-hex-wide bg-violet/20 px-6 py-1.5 font-display text-sm uppercase tracking-widest text-[#c9a4ff]">
              {equippedTitle}
            </span>
          </div>
        )}
      </SystemWindow>

      {/* ── Détail des statistiques (déplacé depuis le Hub) ── */}
      <SystemWindow title="Statistiques" showSystemTag={false} tone="cyan">
        <div className="space-y-3.5">
          {STAT_ORDER.map((code) => {
            const s = statsByCode.get(code);
            return (
              <StatBar key={code} stat={code} level={s?.level ?? 1} currentXp={s?.current_xp ?? 0} />
            );
          })}
        </div>
      </SystemWindow>

      {/* ── Fantôme ── */}
      <SystemWindow title="Toi vs ton Fantôme" tone="ghost">
        {ghostGlobalLevel === null ? (
          <p className="text-sm text-text-muted">
            Pas encore de Fantôme à affronter — reviens dans 30 jours pour voir apparaître ton
            rival d&apos;il y a un mois.
          </p>
        ) : (
          <>
            <div className="flex items-center justify-between">
              <div className="text-center">
                <p className="font-display text-2xl text-text-primary">{globalLevel}</p>
                <p className="text-[10px] uppercase tracking-widest text-text-muted">
                  Aujourd&apos;hui
                </p>
              </div>
              <div
                className={`font-display text-3xl ${
                  globalDelta !== null && globalDelta >= 0 ? "text-cyan" : "text-danger"
                }`}
              >
                {globalDelta !== null && globalDelta >= 0 ? "+" : ""}
                {globalDelta}
              </div>
              <div className="text-center">
                <p className="font-display text-2xl text-ghost">{ghostGlobalLevel}</p>
                <p className="text-[10px] uppercase tracking-widest text-text-muted">Il y a 30 j</p>
              </div>
            </div>
            <div className="mt-4 grid grid-cols-5 gap-2">
              {STAT_ORDER.map((code) => {
                const delta = (statsByCode.get(code)?.level ?? 1) - (ghostStats[code]?.level ?? 1);
                return (
                  <div key={code} className="text-center">
                    <p className="text-[10px] text-text-muted">{code}</p>
                    <p
                      className={`font-display text-sm tabular-nums ${
                        delta >= 0 ? "text-cyan" : "text-danger"
                      }`}
                    >
                      {delta >= 0 ? "+" : ""}
                      {delta}
                    </p>
                  </div>
                );
              })}
            </div>
          </>
        )}
      </SystemWindow>

      {/* ── Armée des Ombres ── */}
      <SystemWindow title="Armée des Ombres" showSystemTag={false}>
        {!shadows || shadows.length === 0 ? (
          <p className="text-sm text-text-muted">
            Aucune Ombre extraite pour l&apos;instant. Complète une habitude 100 fois pour extraire
            ta première.
          </p>
        ) : (
          <div className="flex flex-wrap gap-4">
            {shadows.map((s) => (
              <div key={s.id} className="flex flex-col items-center gap-1">
                <ShadowSilhouette grade={s.grade as ShadowGrade} showLabel={false} />
                <span className="text-[10px] text-violet">{gradeLabel(s.grade as ShadowGrade)}</span>
                <span
                  className="max-w-[5rem] truncate text-[10px] text-text-muted"
                  title={s.name}
                >
                  {s.name}
                </span>
              </div>
            ))}
          </div>
        )}
      </SystemWindow>

      {/* ── Journal ── */}
      <SystemWindow title="Journal du Chasseur" showSystemTag={false}>
        {!journalEntries || journalEntries.length === 0 ? (
          <p className="text-sm text-text-muted">Ton premier récap arrive dimanche à 20h.</p>
        ) : (
          <div className="space-y-3">
            {journalEntries.map((entry) => {
              const p = entry.payload as {
                quests_completed: number;
                xp_gained: number;
                xp_lost: number;
                boss_damage: number;
                shadows_extracted: number;
                titles_unlocked: number;
                completion_rate: number;
              };
              return (
                <div key={entry.week_start} className="border border-border-glow/60 p-3 text-xs text-text-muted">
                  <div className="mb-1.5 flex items-center justify-between">
                    <span className="font-display text-sm text-text-primary">
                      Semaine du {entry.week_start}
                    </span>
                    <a
                      href={`/profil/journal/${entry.week_start}/image`}
                      className="text-cyan hover:underline"
                    >
                      Partager l&apos;image →
                    </a>
                  </div>
                  <p>
                    {p.quests_completed} quêtes · +{p.xp_gained} / -{p.xp_lost} XP · taux{" "}
                    {Math.round(p.completion_rate * 100)}%
                    {p.boss_damage > 0 ? ` · ${p.boss_damage} dégâts au boss` : ""}
                    {p.shadows_extracted > 0 ? ` · ${p.shadows_extracted} Ombre(s)` : ""}
                    {p.titles_unlocked > 0 ? ` · ${p.titles_unlocked} titre(s)` : ""}
                  </p>
                </div>
              );
            })}
          </div>
        )}
      </SystemWindow>

      {/* ── Collection ── */}
      <SystemWindow title="Collection" showSystemTag={false}>
        <div className="grid grid-cols-2 gap-3 text-sm">
          <div className="border border-border-glow/60 p-3">
            <p className="font-display text-lg text-text-primary">{titles.length}</p>
            <p className="text-xs text-text-muted">
              Titre{titles.length > 1 ? "s" : ""} débloqué{titles.length > 1 ? "s" : ""}
            </p>
            {titles.length > 0 && (
              <p className="mt-1 text-[11px] text-[#c9a4ff]">
                {titles.map((t) => t.name).join(" · ")}
              </p>
            )}
          </div>
          <div className="border border-border-glow/60 p-3">
            <p className="font-display text-lg text-text-primary">{itemCount}</p>
            <p className="text-xs text-text-muted">Objet{itemCount > 1 ? "s" : ""} en inventaire</p>
          </div>
        </div>
      </SystemWindow>

      {/* ── Réglages ── */}
      <SystemWindow title="Réglages" showSystemTag={false}>
        <p className="mb-3 text-xs text-text-muted">
          Reçois les rappels [SYSTÈME] avant l&apos;heure limite de tes quêtes (T-30, T-15).
        </p>
        <PushSubscribeButton />
        <form action="/auth/signout" method="post" className="mt-4">
          <button type="submit" className="sys-cta sys-cta--ghost w-full py-2 hover:border-danger hover:text-danger">
            Se déconnecter
          </button>
        </form>
      </SystemWindow>
    </div>
  );
}

function gradeLabel(grade: ShadowGrade): string {
  return { soldat: "Soldat", chevalier: "Chevalier", general: "Général", marechal: "Maréchal" }[
    grade
  ];
}

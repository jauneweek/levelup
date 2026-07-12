import Link from "next/link";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { SystemWindow } from "@/components/system-window";
import { HexChip } from "@/components/hex-chip";
import { ShadowSilhouette, type ShadowGrade } from "@/components/shadow-silhouette";
import { STAT_LABELS, type StatCode } from "@/lib/xp";
import { offsetDateInTimezone } from "@/lib/date";

const STAT_ORDER: StatCode[] = ["FOR", "INT", "SAG", "PRO", "END"];

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

  const [{ data: stats }, { data: ghostSnapshot }, { data: shadows }, { data: journalEntries }] =
    await Promise.all([
      supabase.from("user_stats").select("stat, level, current_xp").eq("user_id", user.id),
      supabase
        .from("daily_snapshots")
        .select("global_level, stats")
        .eq("date", ghostDate)
        .maybeSingle(),
      supabase
        .from("shadows")
        .select("id, name, grade, extracted_at, habits(stat)")
        .order("extracted_at", { ascending: false }),
      supabase
        .from("journal_entries")
        .select("week_start, payload")
        .order("week_start", { ascending: false }),
    ]);

  const statsByCode = new Map((stats ?? []).map((s) => [s.stat as StatCode, s]));
  const ghostStats = (ghostSnapshot?.stats ?? {}) as Record<string, { level: number; current_xp: number }>;
  const globalLevel = profile?.global_level ?? 1;
  const ghostGlobalLevel = ghostSnapshot?.global_level ?? null;
  const globalDelta = ghostGlobalLevel !== null ? globalLevel - ghostGlobalLevel : null;

  return (
    <main className="flex-1 p-6">
      <div className="mx-auto max-w-2xl space-y-6">
        <Link href="/" className="text-xs text-cyan hover:underline">
          ← Retour au Hub
        </Link>

        <SystemWindow title="Profil du Chasseur">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-text-muted">{profile?.username ?? user.email}</p>
              <p className="mt-1 font-display text-2xl text-text-primary">
                Niveau {globalLevel}
              </p>
            </div>
            <HexChip tone="violet" className="text-base">
              Rang {profile?.rank ?? "E"}
            </HexChip>
          </div>
        </SystemWindow>

        <SystemWindow title="Toi vs ton Fantôme">
          {ghostGlobalLevel === null ? (
            <p className="text-sm text-text-muted">
              Pas encore de Fantôme à affronter — reviens dans 30 jours pour voir
              apparaître ton rival d&apos;il y a un mois.
            </p>
          ) : (
            <>
              <div className="flex items-center justify-between text-sm">
                <span className="text-text-primary">
                  Toi : niv. {globalLevel}
                </span>
                <span
                  className={
                    globalDelta !== null && globalDelta >= 0 ? "text-cyan" : "text-danger"
                  }
                >
                  {globalDelta !== null && globalDelta >= 0 ? "+" : ""}
                  {globalDelta}
                </span>
                <span className="text-ghost">
                  Fantôme (J-30) : niv. {ghostGlobalLevel}
                </span>
              </div>
              <div className="mt-3 space-y-1.5">
                {STAT_ORDER.map((code) => {
                  const current = statsByCode.get(code)?.level ?? 1;
                  const ghost = ghostStats[code]?.level ?? 1;
                  const delta = current - ghost;
                  return (
                    <div key={code} className="flex items-center justify-between text-xs">
                      <span className="text-text-muted">{STAT_LABELS[code]}</span>
                      <span className={delta >= 0 ? "text-cyan" : "text-danger"}>
                        {delta >= 0 ? "+" : ""}
                        {delta}
                      </span>
                    </div>
                  );
                })}
              </div>
            </>
          )}
        </SystemWindow>

        <SystemWindow title="Armée des Ombres" showSystemTag={false}>
          {!shadows || shadows.length === 0 ? (
            <p className="text-sm text-text-muted">
              Aucune Ombre extraite pour l&apos;instant. Complète une habitude 100
              fois pour en extraire une.
            </p>
          ) : (
            <div className="flex flex-wrap gap-4">
              {shadows.map((s) => (
                <div key={s.id} className="flex flex-col items-center gap-1">
                  <ShadowSilhouette grade={s.grade as ShadowGrade} />
                  <span className="max-w-[5rem] truncate text-[10px] text-text-primary" title={s.name}>
                    {s.name}
                  </span>
                </div>
              ))}
            </div>
          )}
        </SystemWindow>

        <SystemWindow title="Journal du Chasseur" showSystemTag={false}>
          {!journalEntries || journalEntries.length === 0 ? (
            <p className="text-sm text-text-muted">
              Ton premier récap arrive dimanche à 20h.
            </p>
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
                  <div
                    key={entry.week_start}
                    className="rounded border border-border-glow p-3 text-xs text-text-muted"
                  >
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
                      {p.quests_completed} quêtes · +{p.xp_gained} XP / -{p.xp_lost} XP · taux{" "}
                      {Math.round(p.completion_rate * 100)}%
                      {p.boss_damage > 0 ? ` · ${p.boss_damage} dégâts au boss` : ""}
                      {p.shadows_extracted > 0 ? ` · ${p.shadows_extracted} Ombre(s) extraite(s)` : ""}
                      {p.titles_unlocked > 0 ? ` · ${p.titles_unlocked} titre(s) débloqué(s)` : ""}
                    </p>
                  </div>
                );
              })}
            </div>
          )}
        </SystemWindow>
      </div>
    </main>
  );
}

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { SystemWindow } from "@/components/system-window";

type JournalPayload = {
  quests_completed: number;
  xp_gained: number;
  xp_lost: number;
  boss_damage: number;
  shadows_extracted: number;
  titles_unlocked: number;
  completion_rate: number;
  completion_rate_prev: number;
};

export default async function JournalPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect("/login");

  const { data: entries } = await supabase
    .from("journal_entries")
    .select("week_start, payload")
    .order("week_start", { ascending: false });

  return (
    <div className="space-y-5">
      <h1 className="px-1 font-display text-xl uppercase tracking-widest text-text-primary">
        Journal du Chasseur
      </h1>

      {!entries || entries.length === 0 ? (
        <SystemWindow title="Aucun récap">
          <p className="text-sm text-text-muted">
            Le Système rédige ton rapport chaque dimanche à 20h. Le premier arrive bientôt.
          </p>
        </SystemWindow>
      ) : (
        entries.map((entry) => {
          const p = entry.payload as JournalPayload;
          const delta = Math.round((p.completion_rate - p.completion_rate_prev) * 100);
          return (
            <SystemWindow key={entry.week_start} title={`Semaine du ${entry.week_start}`}>
              <ul className="space-y-1.5 text-sm text-text-muted">
                <li>
                  <b className="font-display tabular-nums text-text-primary">
                    {p.quests_completed}
                  </b>{" "}
                  quêtes complétées
                </li>
                <li>
                  <b className="font-display tabular-nums text-cyan">+{p.xp_gained}</b> XP gagnés ·{" "}
                  <b className="font-display tabular-nums text-text-muted">−{p.xp_lost}</b> XP perdus
                </li>
                <li>
                  Taux de complétion{" "}
                  <b className="font-display tabular-nums text-cyan">
                    {Math.round(p.completion_rate * 100)} %
                  </b>{" "}
                  <span className={delta >= 0 ? "text-cyan" : "text-danger"}>
                    ({delta >= 0 ? "+" : ""}
                    {delta})
                  </span>
                </li>
                {p.boss_damage > 0 && (
                  <li className="text-danger">
                    {p.boss_damage} dégât{p.boss_damage > 1 ? "s" : ""} infligé
                    {p.boss_damage > 1 ? "s" : ""} au Boss
                  </li>
                )}
                {p.shadows_extracted > 0 && (
                  <li className="text-violet">
                    {p.shadows_extracted} Ombre{p.shadows_extracted > 1 ? "s" : ""} extraite
                    {p.shadows_extracted > 1 ? "s" : ""}
                  </li>
                )}
                {p.titles_unlocked > 0 && (
                  <li className="text-amber">
                    {p.titles_unlocked} titre{p.titles_unlocked > 1 ? "s" : ""} débloqué
                    {p.titles_unlocked > 1 ? "s" : ""}
                  </li>
                )}
              </ul>

              <a
                href={`/profil/journal/${entry.week_start}/image`}
                className="sys-cta mt-5 w-full"
                target="_blank"
                rel="noreferrer"
              >
                Partager l&apos;image
              </a>
            </SystemWindow>
          );
        })
      )}
    </div>
  );
}

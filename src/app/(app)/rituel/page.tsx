import Link from "next/link";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { getSessionUser } from "@/lib/auth";
import { SystemWindow } from "@/components/system-window";
import { SegmentTabs } from "@/components/segment-tabs";
import { TodoQuickAdd } from "@/components/todo-quick-add";
import { STAT_LABELS, type StatCode } from "@/lib/xp";
import { getDayState } from "@/lib/quests";
import { tomorrowInTimezone } from "@/lib/date";

const EVENT_LABELS: Record<string, string> = {
  potion: "🧪 Potion d'Énergie active — XP ×2 si journée parfaite.",
  chest: "💰 Coffre mystère — s'ouvre à 3 quêtes complétées.",
  rush: "⚡ Heure de rush — une quête vaut XP ×2 avant midi.",
  cursed: "🌑 Jour maudit — pénalités doublées aujourd'hui.",
};

function hourInTimezone(tz: string): number {
  return Number(
    new Intl.DateTimeFormat("en-US", { timeZone: tz, hour: "numeric", hour12: false }).format(
      new Date(),
    ),
  );
}

function dateLabel(tz: string): string {
  return new Intl.DateTimeFormat("fr-FR", {
    timeZone: tz,
    weekday: "long",
    day: "numeric",
    month: "long",
  }).format(new Date());
}

export default async function RituelPage() {
  const supabase = await createClient();
  const user = await getSessionUser();
  if (!user) redirect("/login");

  const day = await getDayState();
  const timezone = day?.timezone ?? "UTC";
  const today = day?.today ?? "";
  const tomorrow = tomorrowInTimezone(timezone);
  const hour = hourInTimezone(timezone);
  const defaultSegment = hour < 14 ? "matin" : "soir";

  const [{ data: profile }, { data: eventToday }, { data: boss }, { data: secret }, { data: tomorrowTodos }] =
    await Promise.all([
      supabase.from("profiles").select("rank").eq("id", user.id).maybeSingle(),
      supabase.from("events_log").select("event_type").eq("date", today).maybeSingle(),
      supabase.from("boss_fights").select("hp, max_hp").eq("status", "active").maybeSingle(),
      supabase.from("secret_quests").select("revealed").eq("date", today).maybeSingle(),
      supabase
        .from("todos")
        .select("id, title, stat, difficulty")
        .eq("date", tomorrow)
        .order("created_at", { ascending: true }),
    ]);

  const rank = profile?.rank ?? "E";
  const habitCount = (day?.habits ?? []).length;
  const todoCount = (day?.todos ?? []).length;
  const eventLabel = eventToday?.event_type ? EVENT_LABELS[eventToday.event_type] : undefined;

  const matin = (
    <div className="space-y-4">
      <SystemWindow title="Briefing du jour">
        <p className="text-sm capitalize text-text-primary">{dateLabel(timezone)}</p>
        <p className="mt-1 text-xs text-text-muted">Bonjour, Chasseur de rang {rank}.</p>
      </SystemWindow>

      <SystemWindow title="Chargement du donjon" showSystemTag={false}>
        <ul className="space-y-2 text-sm">
          <li className="text-text-muted">
            🗓️ <b className="text-text-primary">{habitCount + todoCount} quête(s)</b> chargée(s) —{" "}
            {habitCount} habitude(s)
            {todoCount > 0 ? ` + ${todoCount} todo(s) planifiée(s) hier soir` : ""}.
          </li>
          {eventLabel && <li className="text-amber">{eventLabel}</li>}
          {boss && (
            <li className="text-danger">
              👹 Boss actif — {boss.hp}/{boss.max_hp} PV. Une journée parfaite = 1 dégât.
            </li>
          )}
          {secret && !secret.revealed && (
            <li className="text-cyan">🎁 Une quête cache un trésor aujourd&apos;hui.</li>
          )}
        </ul>
        <Link href="/quetes" className="sys-cta mt-5 w-full">
          Commencer la journée
        </Link>
      </SystemWindow>
    </div>
  );

  const soir = (
    <div className="space-y-4">
      <SystemWindow title="Rituel du soir">
        <p className="text-sm text-text-muted">
          Prépare tes quêtes de demain. L&apos;acte de planifier rapporte{" "}
          <span className="text-cyan">+10 XP Productivité</span> (une fois par soir).
        </p>
      </SystemWindow>

      <SystemWindow title="Ajouter une mission" showSystemTag={false}>
        <TodoQuickAdd date={tomorrow} />
      </SystemWindow>

      <SystemWindow title="Demain" showSystemTag={false} tone="cyan">
        {tomorrowTodos && tomorrowTodos.length > 0 ? (
          <div className="space-y-2">
            {tomorrowTodos.map((t) => (
              <div
                key={t.id}
                className="flex items-center justify-between border border-border-glow/60 p-2.5 text-xs"
              >
                <span className="text-text-primary">📋 {t.title}</span>
                <span className="text-text-muted">{STAT_LABELS[t.stat as StatCode]}</span>
              </div>
            ))}
          </div>
        ) : (
          <p className="text-sm text-text-muted">
            Aucune mission planifiée pour demain. Ajoute-en une ci-dessus.
          </p>
        )}
      </SystemWindow>
    </div>
  );

  return (
    <div className="space-y-5">
      <div className="flex items-baseline justify-between px-1">
        <h1 className="font-display text-xl uppercase tracking-widest text-text-primary">Rituel</h1>
        <span className="font-display text-xs tracking-[0.3em] text-violet">[SYSTÈME]</span>
      </div>
      <SegmentTabs
        segments={[
          { key: "matin", label: "☀ Matin" },
          { key: "soir", label: "☾ Soir" },
        ]}
        panels={{ matin, soir }}
        initial={defaultSegment}
      />
    </div>
  );
}

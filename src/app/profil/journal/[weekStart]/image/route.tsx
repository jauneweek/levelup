import { ImageResponse } from "next/og";
import { createClient } from "@/lib/supabase/server";

export const runtime = "nodejs";

type JournalPayload = {
  quests_completed: number;
  xp_gained: number;
  xp_lost: number;
  boss_damage: number;
  shadows_extracted: number;
  titles_unlocked: number;
  completion_rate: number;
  completion_rate_prev: number;
  ghost_delta: number | null;
  daily_breakdown: Record<string, number>;
};

const COLORS = {
  bg: "#05050A",
  panel: "rgba(18,16,32,0.9)",
  border: "rgba(124,58,237,0.55)",
  violet: "#7C3AED",
  cyan: "#22D3EE",
  amber: "#F59E0B",
  textPrimary: "#EDEDF7",
  textMuted: "#8B8AA3",
};

export async function GET(
  _req: Request,
  { params }: { params: Promise<{ weekStart: string }> },
) {
  const { weekStart } = await params;
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return new Response("not authenticated", { status: 401 });
  }

  const { data: entry } = await supabase
    .from("journal_entries")
    .select("payload")
    .eq("week_start", weekStart)
    .maybeSingle();

  if (!entry) {
    return new Response("journal entry not found", { status: 404 });
  }

  const p = entry.payload as JournalPayload;
  const days = Object.entries(p.daily_breakdown ?? {}).sort(([a], [b]) => a.localeCompare(b));
  const maxDay = Math.max(1, ...days.map(([, count]) => count));
  const deltaPct = Math.round((p.completion_rate - p.completion_rate_prev) * 100);

  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          flexDirection: "column",
          backgroundColor: COLORS.bg,
          padding: "64px 56px",
          fontFamily: "sans-serif",
          color: COLORS.textPrimary,
        }}
      >
        <div
          style={{
            display: "flex",
            flexDirection: "column",
            border: `2px solid ${COLORS.border}`,
            backgroundColor: COLORS.panel,
            borderRadius: 12,
            padding: 48,
            flex: 1,
          }}
        >
          <div style={{ display: "flex", fontSize: 28, color: COLORS.violet, letterSpacing: 4 }}>
            [SYSTÈME]
          </div>
          <div style={{ display: "flex", fontSize: 44, fontWeight: 700, marginTop: 8 }}>
            Journal du Chasseur
          </div>
          <div style={{ display: "flex", fontSize: 24, color: COLORS.textMuted, marginTop: 4 }}>
            Semaine du {weekStart}
          </div>

          <div style={{ display: "flex", flexDirection: "column", marginTop: 48, gap: 20 }}>
            <Row label="Quêtes complétées" value={String(p.quests_completed)} color={COLORS.textPrimary} />
            <Row label="XP gagnés" value={`+${p.xp_gained}`} color={COLORS.cyan} />
            <Row label="XP perdus" value={`-${p.xp_lost}`} color={COLORS.textMuted} />
            {p.boss_damage > 0 && (
              <Row label="Dégâts infligés au boss" value={String(p.boss_damage)} color="#EF4444" />
            )}
            {p.shadows_extracted > 0 && (
              <Row label="Ombres extraites" value={String(p.shadows_extracted)} color={COLORS.violet} />
            )}
            {p.titles_unlocked > 0 && (
              <Row label="Titres débloqués" value={String(p.titles_unlocked)} color={COLORS.amber} />
            )}
            <Row
              label="Taux de complétion"
              value={`${Math.round(p.completion_rate * 100)}% (${deltaPct >= 0 ? "+" : ""}${deltaPct}%)`}
              color={COLORS.cyan}
            />
            {p.ghost_delta !== null && (
              <Row
                label="Avance sur ton Fantôme"
                value={`${p.ghost_delta >= 0 ? "+" : ""}${p.ghost_delta} niveaux`}
                color="#93C5FD"
              />
            )}
          </div>

          <div style={{ display: "flex", alignItems: "flex-end", gap: 16, marginTop: 56, height: 160 }}>
            {days.map(([date, count]) => (
              <div key={date} style={{ display: "flex", flexDirection: "column", alignItems: "center", flex: 1 }}>
                <div
                  style={{
                    display: "flex",
                    width: "100%",
                    height: Math.max(8, Math.round((count / maxDay) * 120)),
                    backgroundColor: COLORS.violet,
                    borderRadius: 4,
                  }}
                />
                <div style={{ display: "flex", fontSize: 16, color: COLORS.textMuted, marginTop: 8 }}>
                  {date.slice(8, 10)}
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>
    ),
    { width: 1080, height: 1920 },
  );
}

function Row({ label, value, color }: { label: string; value: string; color: string }) {
  return (
    <div style={{ display: "flex", justifyContent: "space-between", fontSize: 28 }}>
      <div style={{ display: "flex", color: COLORS.textMuted }}>{label}</div>
      <div style={{ display: "flex", color, fontWeight: 700 }}>{value}</div>
    </div>
  );
}

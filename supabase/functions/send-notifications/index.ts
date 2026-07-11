// LEVELUP — Edge Function `send-notifications` (SPEC §4.1)
//
// Dispatcher fin : toute la logique (sélection T-30/T-15, escalade,
// anti-répétition, interpolation) vit en SQL (get_due_notifications(),
// migration 0004). Depuis M4, une 2e source vient s'ajouter :
// get_due_queued_notifications() (migration 0005) — annonces
// événementielles (boss, événements aléatoires, titres, bouclier,
// rédemption) déposées par close_day()/draw_daily_event() dans
// notification_queue. Cette fonction ne fait que :
//   1. Appeler les deux sources (service role, RLS bypass).
//   2. Envoyer chaque notification via web-push (VAPID) à tous les
//      appareils abonnés du user concerné.
//   3. Logger via record_notification_sent() (anti-répétition future) et,
//      pour la file événementielle, marquer la ligne consommée via
//      record_queue_notification_sent().
//   4. Nettoyer les souscriptions mortes (410/404).
//
// Déclenchée par pg_cron (*/5 min) → net.http_post vers cette fonction.
import { createClient } from "npm:@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const VAPID_PUBLIC_KEY = Deno.env.get("VAPID_PUBLIC_KEY")!;
const VAPID_PRIVATE_KEY = Deno.env.get("VAPID_PRIVATE_KEY")!;
const VAPID_SUBJECT = Deno.env.get("VAPID_SUBJECT")!;

webpush.setVapidDetails(VAPID_SUBJECT, VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY);

type DueNotification = {
  user_id: string;
  habit_id: string | null;
  template_id: string;
  trigger_type: string;
  body: string;
};

type DueQueuedNotification = DueNotification & { queue_id: string };

type PushSubscriptionRow = {
  id: string;
  endpoint: string;
  keys: { p256dh: string; auth: string };
};

Deno.serve(async (_req: Request) => {
  const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

  const { data: due, error: dueError } = await supabase.rpc(
    "get_due_notifications",
  );
  if (dueError) {
    return new Response(JSON.stringify({ error: dueError.message }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }

  const { data: queued, error: queuedError } = await supabase.rpc(
    "get_due_queued_notifications",
  );
  if (queuedError) {
    return new Response(JSON.stringify({ error: queuedError.message }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }

  const rows = (due ?? []) as DueNotification[];
  const queuedRows = (queued ?? []) as DueQueuedNotification[];
  let sent = 0;
  let failed = 0;
  let logged = 0;

  const dispatch = async (userId: string, body: string) => {
    const { data: subs } = await supabase
      .from("push_subscriptions")
      .select("id, endpoint, keys")
      .eq("user_id", userId);

    for (const sub of (subs ?? []) as PushSubscriptionRow[]) {
      try {
        await webpush.sendNotification(
          {
            endpoint: sub.endpoint,
            keys: { p256dh: sub.keys.p256dh, auth: sub.keys.auth },
          },
          JSON.stringify({ title: "LEVELUP", body, url: "/" }),
        );
        sent++;
      } catch (err) {
        failed++;
        const statusCode = (err as { statusCode?: number }).statusCode;
        if (statusCode === 404 || statusCode === 410) {
          await supabase.from("push_subscriptions").delete().eq("id", sub.id);
        }
      }
    }
  };

  for (const row of rows) {
    await dispatch(row.user_id, row.body);

    const { error: logError } = await supabase.rpc(
      "record_notification_sent",
      {
        p_user_id: row.user_id,
        p_template_id: row.template_id,
        p_habit_id: row.habit_id,
      },
    );
    if (!logError) logged++;
  }

  for (const row of queuedRows) {
    await dispatch(row.user_id, row.body);

    const { error: logError } = await supabase.rpc(
      "record_notification_sent",
      {
        p_user_id: row.user_id,
        p_template_id: row.template_id,
        p_habit_id: row.habit_id,
      },
    );
    if (!logError) logged++;

    await supabase.rpc("record_queue_notification_sent", {
      p_queue_id: row.queue_id,
    });
  }

  return new Response(
    JSON.stringify({
      due: rows.length,
      queued: queuedRows.length,
      sent,
      failed,
      logged,
    }),
    { headers: { "Content-Type": "application/json" } },
  );
});

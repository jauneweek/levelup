"use client";

import { useEffect, useState } from "react";
import { isPushSupported, subscribeToPush } from "@/lib/push";
import { savePushSubscription } from "@/app/notifications/actions";

export function PushSubscribeButton() {
  const [status, setStatus] = useState<
    "checking" | "unsupported" | "denied" | "subscribed" | "idle" | "loading" | "error"
  >("checking");
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    async function check() {
      if (!isPushSupported()) {
        setStatus("unsupported");
        return;
      }
      if (Notification.permission === "denied") {
        setStatus("denied");
        return;
      }
      try {
        const registration = await navigator.serviceWorker.ready;
        const existing = await registration.pushManager.getSubscription();
        setStatus(existing ? "subscribed" : "idle");
      } catch {
        setStatus("idle");
      }
    }
    check();
  }, []);

  async function onSubscribe() {
    setStatus("loading");
    setError(null);
    try {
      const permission = await Notification.requestPermission();
      if (permission !== "granted") {
        setStatus("denied");
        return;
      }
      const sub = await subscribeToPush();
      if (!sub.endpoint || !sub.keys) {
        throw new Error("souscription invalide (endpoint/keys manquants)");
      }
      await savePushSubscription({
        endpoint: sub.endpoint,
        keys: { p256dh: sub.keys.p256dh, auth: sub.keys.auth },
      });
      setStatus("subscribed");
    } catch (e) {
      setError(e instanceof Error ? e.message : "erreur inconnue");
      setStatus("error");
    }
  }

  if (status === "checking") return null;

  if (status === "unsupported") {
    return (
      <p className="text-xs text-text-muted">
        Notifications non supportées par ce navigateur. Sur iPhone : ajoute
        d&apos;abord LEVELUP à l&apos;écran d&apos;accueil (Safari → Partager →
        Sur l&apos;écran d&apos;accueil), puis réessaie depuis l&apos;app
        installée.
      </p>
    );
  }

  if (status === "subscribed") {
    return <p className="text-xs text-cyan">🔔 Notifications activées.</p>;
  }

  if (status === "denied") {
    return (
      <p className="text-xs text-danger">
        Notifications bloquées. Active-les dans les réglages de ton
        navigateur/iPhone pour recevoir les rappels du Système.
      </p>
    );
  }

  return (
    <div>
      <button
        onClick={onSubscribe}
        disabled={status === "loading"}
        className="rounded bg-violet px-4 py-2 text-sm font-medium text-white hover:opacity-90 disabled:opacity-50"
      >
        {status === "loading" ? "Activation…" : "🔔 Activer les notifications"}
      </button>
      {error && <p className="mt-2 text-xs text-danger">{error}</p>}
    </div>
  );
}

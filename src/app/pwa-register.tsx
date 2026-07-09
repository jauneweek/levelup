"use client";

import { useEffect } from "react";

/**
 * Enregistre le service worker minimal (offline shell + installabilité).
 * Le push Web (VAPID) sera branché en M3 — cf. SPEC §4 / roadmap.
 */
export function PwaRegister() {
  useEffect(() => {
    if (typeof window === "undefined") return;
    if (!("serviceWorker" in navigator)) return;
    if (process.env.NODE_ENV !== "production") return; // évite le cache SW en dev

    const onLoad = () => {
      navigator.serviceWorker
        .register("/sw.js", { scope: "/" })
        .catch(() => {
          /* silencieux : l'app fonctionne sans SW */
        });
    };

    window.addEventListener("load", onLoad);
    return () => window.removeEventListener("load", onLoad);
  }, []);

  return null;
}

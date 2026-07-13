/**
 * Retour haptique léger sur les interactions.
 *
 * ⚠️ Limite réelle à connaître : **iOS/Safari n'implémente PAS l'API Vibration**
 * (`navigator.vibrate`). Ça marche sur Android/Chrome, et c'est un no-op
 * silencieux sur iPhone — y compris en PWA installée. Il n'existe aujourd'hui
 * aucun moyen fiable et standard de déclencher le Taptic Engine depuis le web
 * sur iOS. On garde l'appel (gratuit, dégradation propre) et on compense sur
 * iPhone par le feedback visuel + sonore.
 */
export type HapticKind = "tap" | "success" | "warn";

const PATTERNS: Record<HapticKind, number | number[]> = {
  tap: 10,
  success: [14, 30, 22],
  warn: [30, 40, 30],
};

export function haptic(kind: HapticKind = "tap") {
  if (typeof navigator === "undefined") return;
  const nav = navigator as Navigator & { vibrate?: (p: number | number[]) => boolean };
  if (typeof nav.vibrate !== "function") return;
  try {
    nav.vibrate(PATTERNS[kind]);
  } catch {
    /* no-op */
  }
}

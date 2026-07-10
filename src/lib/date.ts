const WEEKDAY_ORDER = [
  "Monday",
  "Tuesday",
  "Wednesday",
  "Thursday",
  "Friday",
  "Saturday",
  "Sunday",
] as const;

/**
 * Date (YYYY-MM-DD) et jour ISO (1=lundi..7=dimanche) "aujourd'hui" dans le
 * fuseau du user. Sert uniquement à filtrer l'affichage du Hub — la vérité
 * de jeu (idempotence, pénalités) vit dans les fonctions Postgres qui
 * calculent `now() at time zone tz` côté serveur (SPEC §8).
 */
export function todayInTimezone(timezone: string): {
  dateStr: string;
  isoWeekday: number;
} {
  const now = new Date();

  const dateStr = new Intl.DateTimeFormat("en-CA", {
    timeZone: timezone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(now); // en-CA => YYYY-MM-DD

  const weekdayName = new Intl.DateTimeFormat("en-US", {
    timeZone: timezone,
    weekday: "long",
  }).format(now);

  const isoWeekday = WEEKDAY_ORDER.indexOf(
    weekdayName as (typeof WEEKDAY_ORDER)[number],
  ) + 1;

  return { dateStr, isoWeekday };
}

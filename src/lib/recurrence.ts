/**
 * Vocabulaire du quota (SPEC §3.5.1).
 *
 * Volontairement isolé de `quests.ts` : ce dernier importe le client Supabase
 * serveur (donc `next/headers`), et les composants CLIENT (formulaire, cartes,
 * filtres) ont besoin de ces libellés. Les mélanger faisait remonter du code
 * serveur dans le bundle navigateur — et la compilation le refuse, à raison.
 */
export type Recurrence = "daily" | "weekly" | "monthly" | "yearly" | "once";

export const RECURRENCE_LABELS: Record<Recurrence, string> = {
  daily: "Journalière",
  weekly: "Hebdomadaire",
  monthly: "Mensuelle",
  yearly: "Annuelle",
  once: "Unique",
};

/** Forme courte pour les chips : la carte est étroite. */
export const RECURRENCE_SHORT: Record<Recurrence, string> = {
  daily: "jour",
  weekly: "semaine",
  monthly: "mois",
  yearly: "an",
  once: "unique",
};

/** « 3 fois par semaine » — l'unité que le quota compte. */
export const PERIOD_NOUN: Record<Recurrence, string> = {
  daily: "jour",
  weekly: "semaine",
  monthly: "mois",
  yearly: "an",
  once: "une seule fois",
};

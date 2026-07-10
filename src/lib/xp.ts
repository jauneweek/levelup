export type StatCode = "FOR" | "INT" | "SAG" | "PRO" | "END";

export const STAT_LABELS: Record<StatCode, string> = {
  FOR: "Force",
  INT: "Intelligence",
  SAG: "Sagesse",
  PRO: "Productivité",
  END: "Endurance",
};

export const DIFFICULTY_XP = { easy: 10, medium: 25, hard: 50 } as const;

/**
 * Formule de niveau verrouillée (SPEC §3.3) : 100 × N^1.5 (arrondi).
 * Dupliquée ici uniquement pour l'affichage (barre de progression) —
 * la source de vérité XP/niveaux est `complete_habit()` côté serveur.
 */
export function xpToNextLevel(level: number): number {
  return Math.round(100 * Math.pow(level, 1.5));
}

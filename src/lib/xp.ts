export type StatCode = "FOR" | "INT" | "SAG" | "PRO" | "END";

export const STAT_LABELS: Record<StatCode, string> = {
  FOR: "Force",
  INT: "Intelligence",
  SAG: "Sagesse",
  PRO: "Productivité",
  END: "Endurance",
};

export const DIFFICULTY_XP = { easy: 100, medium: 250, hard: 500 } as const;

/**
 * ── Le RADAR : la capacité ───────────────────────────────────────────────────
 * XP absolue. Dix quêtes difficiles par jour font un grand radar, trois faciles
 * un petit : c'est ta vraie vie, elle n'a pas à être normalisée.
 * Seuil d'un niveau de stat : 100 × N^1.5 (SPEC §3.3).
 */
export function xpToNextLevel(level: number): number {
  return Math.round(100 * Math.pow(level, 1.5));
}

/* ── Le CHASSEUR : la discipline ────────────────────────────────────────────
 * 100 niveaux par rang. Au 100e, on passe au rang suivant et le compteur repart
 * à 1 — une promotion, jamais une perte (SPEC §8).
 *
 * L'XP du Chasseur, elle, est NORMALISÉE : une journée pleine vaut 1000 points,
 * que tu aies 3 quêtes ou 10. Sans ça, celui qui en fait 10 atteindrait le rang
 * max en 3 mois et celui qui en fait 3 en mettrait 20 — le rang ne voudrait
 * plus rien dire. Le calcul vit côté serveur (`grant_hunter_xp`) ; ici on ne
 * fait qu'afficher.
 */
export type HunterRank = "E" | "D" | "C" | "B" | "A" | "S" | "M";

export const RANK_LABELS: Record<HunterRank, string> = {
  E: "Rang E",
  D: "Rang D",
  C: "Rang C",
  B: "Rang B",
  A: "Rang A",
  S: "Rang S",
  M: "Monarque",
};

const LEVELS_PER_RANK = 100;

/** Coût du niveau N. 100 au tout premier — une seule quête facile suffit. */
export function hunterXpToNext(level: number): number {
  return 100 + Math.round(1.3 * (Math.max(1, level) - 1));
}

/** Le niveau AFFICHÉ : 1 à 100 à l'intérieur du rang courant. */
export function hunterLevelInRank(level: number): number {
  if (level > 600) return level - 600; // Monarque : le compteur continue
  return ((level - 1) % LEVELS_PER_RANK) + 1;
}

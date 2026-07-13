import type { StatCode } from "@/lib/xp";

/** Ce que le client apprend d'une complétion — de quoi jouer le bon son. */
export type CompleteResult = {
  xpEarned: number;
  stat: StatCode;
  statLevel: number;
  leveledUp: boolean;
};

/**
 * Lit la réponse de `complete_habit` / `complete_habit_express` /
 * `complete_todo`.
 *
 * La montée de niveau est DÉDUITE, pas demandée : la fonction SQL ne renvoie
 * pas de drapeau, et aller relire le niveau d'avant coûterait un aller-retour
 * supplémentaire sur le geste le plus fréquent de l'app. Or la réponse suffit.
 *
 * Côté SQL : `stat_xp := stat_xp + gagné`, puis tant que `stat_xp >= seuil` on
 * retranche le seuil et on monte d'un niveau.
 *   — sans level-up : stat_xp = ancien_xp + gagné, donc stat_xp >= gagné ;
 *   — avec level-up : on a retranché au moins un seuil, or l'ancien XP est par
 *     construction toujours SOUS son seuil, donc stat_xp < gagné.
 * Les deux cas sont disjoints : `stat_xp < xp_earned` ⟺ le niveau a monté.
 *
 * Renvoie `null` quand rien ne s'est passé (quête déjà validée) : pas de son.
 */
export function parseCompleteResult(data: unknown): CompleteResult | null {
  if (!data || typeof data !== "object") return null;
  const d = data as Record<string, unknown>;
  if (d.already_completed) return null;

  const xpEarned = Number(d.xp_earned ?? 0);
  const remaining = Number(d.stat_xp ?? 0);

  return {
    xpEarned,
    stat: String(d.stat ?? "FOR") as StatCode,
    statLevel: Number(d.stat_level ?? 1),
    leveledUp: remaining < xpEarned,
  };
}

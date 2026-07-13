import type { StatCode } from "@/lib/xp";

/** Ce que le client apprend d'une complétion — de quoi jouer le bon son. */
export type CompleteResult = {
  xpEarned: number;
  stat: StatCode;
  statLevel: number;
  /** Le RADAR a monté (capacité). Discret : la barre de la stat bouge. */
  statLeveledUp: boolean;
  /** Le CHASSEUR a monté (discipline). C'est LUI qu'on fête. */
  hunterLeveledUp: boolean;
  /** Niveau affiché dans le rang (1-100) — décide de la fanfare des paliers ronds. */
  hunterLevelInRank: number;
  /** Changement de rang : le moment le plus important du jeu. */
  rankedUp: boolean;
};

/**
 * Lit la réponse de `complete_habit` / `complete_habit_express` / `complete_todo`.
 *
 * La montée de niveau du RADAR est DÉDUITE, pas demandée : la fonction SQL ne
 * renvoie pas de drapeau, et aller relire le niveau d'avant coûterait un
 * aller-retour de plus sur le geste le plus fréquent de l'app. Or la réponse
 * suffit — côté SQL, `stat_xp += gagné` puis, tant que `stat_xp >= seuil`, on
 * retranche le seuil et on monte d'un niveau :
 *   — sans level-up : stat_xp = ancien_xp + gagné, donc stat_xp >= gagné ;
 *   — avec level-up : on a retranché au moins un seuil, or l'ancien XP est par
 *     construction toujours SOUS son seuil, donc stat_xp < gagné.
 * Les deux cas sont disjoints : `stat_xp < xp_earned` ⟺ le niveau a monté.
 *
 * Le CHASSEUR, lui, renvoie ses drapeaux explicitement : sa progression est
 * normalisée par le dû quotidien, elle ne se déduit pas de l'XP gagnée.
 *
 * Renvoie `null` quand rien ne s'est passé (quota déjà rempli) : pas de son.
 */
export function parseCompleteResult(data: unknown): CompleteResult | null {
  if (!data || typeof data !== "object") return null;
  const d = data as Record<string, unknown>;
  if (d.already_completed) return null;

  const xpEarned = Number(d.xp_earned ?? 0);
  const remaining = Number(d.stat_xp ?? 0);

  const hunter = (d.hunter ?? {}) as Record<string, unknown>;

  return {
    xpEarned,
    stat: String(d.stat ?? "FOR") as StatCode,
    statLevel: Number(d.stat_level ?? 1),
    statLeveledUp: remaining < xpEarned,
    hunterLeveledUp: Boolean(hunter.leveled_up),
    hunterLevelInRank: Number(hunter.level_in_rank ?? 1),
    rankedUp: Boolean(hunter.ranked_up),
  };
}

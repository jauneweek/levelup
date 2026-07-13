/**
 * Message du Système affiché sur le Hub (le « miroir »).
 *
 * ⚠️ Ce n'est PAS du contenu de notification push : la banque de templates
 * (`supabase/seed/notification_templates_seed.sql`) reste intouchée. Ce sont
 * des lignes de statut in-app, dérivées de l'état serveur réel, dans la voix
 * du Système. La hiérarchie suit le SPEC :
 *   - §3.9 / §4.4 : en mode slump (7j < 40%), JAMAIS de ton harsh, et « le
 *     Boss se tait » → le slump passe donc AVANT le boss et l'abus.
 *   - §3.16 : le blason se fissure avec les jours d'abus, vire au rouge quand
 *     le boss est actif.
 *   - §3.12 : si le Fantôme (toi il y a 30 jours) te rattrape, il le dit.
 */
export type SystemTone = "violet" | "cyan" | "amber" | "danger" | "ghost";

export type SystemMessage = { tone: SystemTone; text: string };

export type SystemContext = {
  rank: string;
  streak: number;
  pending: number;
  total: number;
  consecutiveAbuseDays: number;
  boss: { hp: number; maxHp: number; daysLeft: number } | null;
  /** niveau global actuel − niveau du Fantôme (J-30). null = pas de Fantôme. */
  ghostDelta: number | null;
  /** taux de complétion 7j < 40% (dernier snapshot connu). */
  isSlump: boolean;
};

export function buildSystemMessage(ctx: SystemContext): SystemMessage {
  const { rank, streak, pending, total, consecutiveAbuseDays, boss, ghostDelta, isSlump } = ctx;

  // 1. Slump — on ne frappe pas quelqu'un à terre (§3.9). Le Boss se tait.
  if (isSlump) {
    return {
      tone: "cyan",
      text:
        pending > 0
          ? "Mode reconstruction. Une seule quête suffit à relancer la machine — commence par la plus facile."
          : "Mode reconstruction. Tu as tenu aujourd'hui. C'est tout ce qui compte.",
    };
  }

  // 2. Boss actif — le blason est corrompu (§3.7 / §3.16).
  if (boss) {
    return {
      tone: "danger",
      text: `Le Boss de la Procrastination te regarde. Blason corrompu. PV ${boss.hp}/${boss.maxHp}. Il te reste ${boss.daysLeft} jour${boss.daysLeft > 1 ? "s" : ""} avant qu'il ne dévore 10 % de ta meilleure stat. Arme : les journées parfaites.`,
    };
  }

  // 3. Jours d'abus consécutifs — le blason se fissure (§3.9 / §3.16).
  if (consecutiveAbuseDays >= 2) {
    const mult = consecutiveAbuseDays >= 3 ? "×2" : "×1.5";
    return {
      tone: "danger",
      text: `${consecutiveAbuseDays} jours d'abus consécutifs. Ton blason se fissure et les pénalités passent à ${mult}. Un 3ᵉ jour fait apparaître le Boss.`,
    };
  }
  if (consecutiveAbuseDays === 1) {
    return {
      tone: "amber",
      text: "Journée d'abus enregistrée hier. Le blason porte une fissure. Le compteur repart aujourd'hui — ne laisse pas ça devenir une série.",
    };
  }

  // 4. Le Fantôme t'a rattrapé (§3.12).
  if (ghostDelta !== null && ghostDelta <= 0) {
    return {
      tone: "ghost",
      text:
        ghostDelta === 0
          ? "Ton Fantôme d'il y a 30 jours vient de te rattraper. Vous êtes à égalité. Reprends l'avantage."
          : `Ton Fantôme d'il y a 30 jours est passé devant toi (${-ghostDelta} niveau${-ghostDelta > 1 ? "x" : ""}). Tu as régressé. Il porte ton nom.`,
    };
  }

  // 5. Journée déjà bouclée.
  if (total > 0 && pending === 0) {
    return {
      tone: "cyan",
      text: `Toutes les quêtes du jour sont validées. Journée parfaite en vue — rang ${rank} confirmé.`,
    };
  }

  // 6. État sain.
  return {
    tone: "violet",
    text:
      pending > 0
        ? `Rang ${rank} maintenu${streak > 0 ? `. Série de ${streak} jour${streak > 1 ? "s" : ""}` : ""}. ${pending} quête${pending > 1 ? "s" : ""} t'attend${pending > 1 ? "ent" : ""} aujourd'hui.`
        : `Rang ${rank} maintenu. Aucune quête programmée aujourd'hui — le donjon est calme.`,
  };
}

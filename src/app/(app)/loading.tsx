/**
 * Squelette de chargement partagé par tous les écrans du jeu.
 *
 * Ce fichier est la principale raison pour laquelle la navigation « laguait » :
 * sans frontière `loading`, Next garde l'ANCIENNE page figée à l'écran pendant
 * tout l'aller-retour serveur — rien ne bouge au tap, l'app paraît bloquée.
 * Avec cette frontière, le routeur peut basculer immédiatement (et pré-charger
 * la coquille des onglets), puis streamer le contenu dedans.
 *
 * Volontairement muet : pas de « Chargement… ». Le Système ne s'excuse pas.
 */
export default function Loading() {
  return (
    <div className="space-y-4 pt-1" aria-busy="true" aria-label="Chargement">
      <div className="skel" style={{ height: 128 }} />
      <div className="skel" style={{ height: 296 }} />
      <div className="skel" style={{ height: 88 }} />
    </div>
  );
}

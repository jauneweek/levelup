/**
 * Retour d'interaction : haptique + son, toujours ensemble.
 *
 * Un seul point d'entrée plutôt qu'un `haptic()` et un `play…()` dupliqués côte
 * à côte à chaque `onClick` — les deux ne doivent jamais diverger, et le jour où
 * l'app passe en natif (haptics iOS réels), il n'y aura qu'ici à toucher.
 *
 * Les deux canaux dégradent proprement : muet si le son est coupé, silencieux
 * si le moteur haptique n'existe pas. Jamais bloquant pour l'interaction.
 */
import { haptic } from "@/lib/haptics";
import { playClose, playOpen, playTap } from "@/lib/sound";

/** Navigation, onglets, filtres, boutons. */
export function tap() {
  haptic("tap");
  playTap();
}

/** Ouverture d'une Fenêtre Système. */
export function openWindow() {
  haptic("tap");
  playOpen();
}

/** Fermeture d'une Fenêtre Système. */
export function closeWindow() {
  haptic("tap");
  playClose();
}

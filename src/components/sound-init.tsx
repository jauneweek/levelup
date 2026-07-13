"use client";

import { useEffect } from "react";
import { initSound } from "@/lib/sound";

/**
 * Arme le moteur audio au premier geste de la session.
 *
 * Obligatoire sur iOS : un AudioContext créé hors d'un geste utilisateur naît
 * « suspended » et le reste. On ne peut donc pas se contenter de le construire
 * au montage — il faut attendre le premier tap, ce que fait `initSound`.
 */
export function SoundInit() {
  useEffect(() => {
    initSound();
  }, []);
  return null;
}

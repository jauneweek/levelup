import { cache } from "react";
import type { User } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/server";

/**
 * Utilisateur de la requête en cours.
 *
 * `supabase.auth.getUser()` n'est pas un simple décodage de cookie : il part en
 * réseau vers GoTrue pour *valider* le JWT (c'est tout l'intérêt — on ne fait
 * jamais confiance au cookie seul). Le coût est donc un aller-retour complet.
 *
 * Or il était appelé jusqu'à 3 fois par navigation — layout, page, et
 * getDayState — soit 3 allers-retours pour répondre à la même question, en
 * série. `cache()` les déduplique sur un même rendu serveur : 1 seul appel
 * réseau, sécurité strictement identique.
 *
 * À utiliser dans TOUT composant serveur. (Le middleware garde son propre
 * appel : il s'exécute avant le rendu React, hors de portée du cache — et il
 * doit de toute façon rafraîchir les cookies de session.)
 */
export const getSessionUser = cache(async (): Promise<User | null> => {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  return user;
});

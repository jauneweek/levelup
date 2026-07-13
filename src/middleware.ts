import { type NextRequest } from "next/server";
import { updateSession } from "@/lib/supabase/middleware";

export async function middleware(request: NextRequest) {
  return await updateSession(request);
}

export const config = {
  matcher: [
    /*
     * Toutes les routes sauf les fichiers statiques.
     *
     * Le middleware fait un `auth.getUser()`, donc un aller-retour réseau vers
     * GoTrue. L'ancien matcher ne filtrait que quelques chemins : chaque son,
     * chaque icône non listée déclenchait donc une validation de JWT complète
     * pour servir un fichier statique. On exclut désormais toute URL portant
     * une extension de fichier.
     */
    "/((?!_next/static|_next/image|.*\\.(?:mp3|svg|png|jpg|jpeg|gif|webp|ico|webmanifest|js|txt)$).*)",
  ],
};

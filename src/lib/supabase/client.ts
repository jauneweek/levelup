import { createBrowserClient } from "@supabase/ssr";
import { supabaseEnv } from "./config";

/** Client Supabase pour les composants client (browser). */
export function createClient() {
  const { url, anonKey } = supabaseEnv();
  return createBrowserClient(url, anonKey);
}

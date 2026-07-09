import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { SystemWindow } from "@/components/system-window";

export default async function Home() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/login");
  }

  const { data: profile } = await supabase
    .from("profiles")
    .select("username, rank, global_level, timezone")
    .eq("id", user.id)
    .maybeSingle();

  return (
    <main className="flex-1 flex items-center justify-center p-6">
      <SystemWindow title="Connexion établie" className="w-full max-w-md">
        <p className="text-text-muted text-sm">Bienvenue, Chasseur.</p>
        <dl className="mt-4 space-y-2 text-sm">
          <div className="flex justify-between gap-4">
            <dt className="text-text-muted">Identifiant</dt>
            <dd className="text-text-primary">{user.email}</dd>
          </div>
          <div className="flex justify-between gap-4">
            <dt className="text-text-muted">Rang</dt>
            <dd className="font-display text-violet">{profile?.rank ?? "—"}</dd>
          </div>
          <div className="flex justify-between gap-4">
            <dt className="text-text-muted">Niveau global</dt>
            <dd className="font-display text-cyan">
              {profile?.global_level ?? "—"}
            </dd>
          </div>
          <div className="flex justify-between gap-4">
            <dt className="text-text-muted">Fuseau</dt>
            <dd className="text-text-primary">{profile?.timezone ?? "—"}</dd>
          </div>
        </dl>

        <p className="mt-6 text-xs text-text-muted">
          Le Hub du Chasseur arrive au milestone M1.
        </p>

        <form action="/auth/signout" method="post" className="mt-6">
          <button
            type="submit"
            className="w-full rounded border border-border-glow bg-transparent px-4 py-2 text-sm text-text-muted transition-colors hover:border-danger hover:text-danger"
          >
            Se déconnecter
          </button>
        </form>
      </SystemWindow>
    </main>
  );
}

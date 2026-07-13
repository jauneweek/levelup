import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { SystemWindow } from "@/components/system-window";
import { PushSubscribeButton } from "@/components/push-subscribe-button";

export default async function ReglagesPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect("/login");

  const { data: profile } = await supabase
    .from("profiles")
    .select("username, timezone")
    .eq("id", user.id)
    .maybeSingle();

  return (
    <div className="space-y-5">
      <h1 className="px-1 font-display text-xl uppercase tracking-widest text-text-primary">
        Réglages
      </h1>

      <SystemWindow title="Rappels du Système">
        <p className="mb-4 text-xs text-text-muted">
          Le Système te prévient avant l&apos;heure limite de tes quêtes (T-30, T-15), et t&apos;envoie
          le briefing du matin. Le ton s&apos;adapte : plus tu ignores, plus il durcit.
        </p>
        <PushSubscribeButton />
      </SystemWindow>

      <SystemWindow title="Compte" showSystemTag={false}>
        <dl className="space-y-2 text-sm">
          <div className="flex justify-between">
            <dt className="text-text-muted">Chasseur</dt>
            <dd className="text-text-primary">{profile?.username ?? user.email}</dd>
          </div>
          <div className="flex justify-between">
            <dt className="text-text-muted">Fuseau horaire</dt>
            <dd className="text-text-primary">{profile?.timezone ?? "UTC"}</dd>
          </div>
        </dl>
        <p className="mt-3 text-[11px] text-text-muted">
          Tout le jeu (minuit, deadlines, rituel) raisonne dans ce fuseau.
        </p>

        <form action="/auth/signout" method="post" className="mt-5">
          <button
            type="submit"
            className="sys-cta sys-cta--ghost w-full py-2.5 hover:border-danger hover:text-danger"
          >
            Se déconnecter
          </button>
        </form>
      </SystemWindow>
    </div>
  );
}

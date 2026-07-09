"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { createClient } from "@/lib/supabase/client";
import { SystemWindow } from "@/components/system-window";

const inputClass =
  "w-full rounded border border-border-glow bg-black/30 px-3 py-2 text-sm text-text-primary placeholder:text-text-muted outline-none focus:border-cyan focus:ring-1 focus:ring-cyan";

export default function SignupPage() {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setMessage(null);
    setLoading(true);

    // Fuseau horaire du navigateur → profiles.timezone (SPEC : tout raisonne en TZ user).
    const timezone =
      Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC";

    const supabase = createClient();
    const { data, error } = await supabase.auth.signUp({
      email,
      password,
      options: {
        data: { timezone },
        emailRedirectTo:
          typeof window !== "undefined"
            ? `${window.location.origin}/auth/callback`
            : undefined,
      },
    });

    if (error) {
      setError(error.message);
      setLoading(false);
      return;
    }

    // Confirmation email désactivée en local → session immédiate.
    if (data.session) {
      router.push("/");
      router.refresh();
      return;
    }

    setMessage(
      "Compte créé. Vérifie ta boîte mail pour confirmer, puis connecte-toi.",
    );
    setLoading(false);
  }

  return (
    <main className="flex-1 flex items-center justify-center p-6">
      <SystemWindow title="Éveil du Chasseur" className="w-full max-w-sm">
        <form onSubmit={onSubmit} className="space-y-4">
          <div className="space-y-1">
            <label htmlFor="email" className="text-xs text-text-muted">
              Email
            </label>
            <input
              id="email"
              type="email"
              autoComplete="email"
              required
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              className={inputClass}
              placeholder="chasseur@levelup.app"
            />
          </div>
          <div className="space-y-1">
            <label htmlFor="password" className="text-xs text-text-muted">
              Mot de passe
            </label>
            <input
              id="password"
              type="password"
              autoComplete="new-password"
              required
              minLength={6}
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              className={inputClass}
              placeholder="6 caractères minimum"
            />
          </div>

          {error && <p className="text-xs text-danger">{error}</p>}
          {message && <p className="text-xs text-cyan">{message}</p>}

          <button
            type="submit"
            disabled={loading}
            className="w-full rounded bg-violet px-4 py-2 text-sm font-medium text-white transition-opacity hover:opacity-90 disabled:opacity-50"
          >
            {loading ? "Éveil en cours…" : "S'éveiller"}
          </button>
        </form>

        <p className="mt-6 text-center text-xs text-text-muted">
          Déjà un Chasseur ?{" "}
          <Link href="/login" className="text-cyan hover:underline">
            Se connecter
          </Link>
        </p>
      </SystemWindow>
    </main>
  );
}

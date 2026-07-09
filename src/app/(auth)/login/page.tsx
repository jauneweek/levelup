"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { createClient } from "@/lib/supabase/client";
import { SystemWindow } from "@/components/system-window";

const inputClass =
  "w-full rounded border border-border-glow bg-black/30 px-3 py-2 text-sm text-text-primary placeholder:text-text-muted outline-none focus:border-cyan focus:ring-1 focus:ring-cyan";

export default function LoginPage() {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setLoading(true);
    const supabase = createClient();
    const { error } = await supabase.auth.signInWithPassword({
      email,
      password,
    });
    if (error) {
      setError(error.message);
      setLoading(false);
      return;
    }
    router.push("/");
    router.refresh();
  }

  return (
    <main className="flex-1 flex items-center justify-center p-6">
      <SystemWindow title="Accès Chasseur" className="w-full max-w-sm">
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
              autoComplete="current-password"
              required
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              className={inputClass}
              placeholder="••••••••"
            />
          </div>

          {error && <p className="text-xs text-danger">{error}</p>}

          <button
            type="submit"
            disabled={loading}
            className="w-full rounded bg-violet px-4 py-2 text-sm font-medium text-white transition-opacity hover:opacity-90 disabled:opacity-50"
          >
            {loading ? "Connexion…" : "Entrer dans le Système"}
          </button>
        </form>

        <p className="mt-6 text-center text-xs text-text-muted">
          Pas encore de compte ?{" "}
          <Link href="/signup" className="text-cyan hover:underline">
            Créer un Chasseur
          </Link>
        </p>
      </SystemWindow>
    </main>
  );
}

import type { ReactNode } from "react";

type SystemWindowProps = {
  /** Titre affiché sous l'en-tête [SYSTÈME]. */
  title?: ReactNode;
  /** Masque le préfixe [SYSTÈME] de l'en-tête si besoin. */
  showSystemTag?: boolean;
  children: ReactNode;
  className?: string;
};

/**
 * Composant signature « Fenêtre Système » (SPEC §9.2).
 * Panneau verre + blur + bordure glow + 4 corner brackets + en-tête [SYSTÈME].
 * TOUT contenu modal / notification in-app doit passer par ce composant.
 */
export function SystemWindow({
  title,
  showSystemTag = true,
  children,
  className = "",
}: SystemWindowProps) {
  return (
    <section className={`system-window sw-enter p-6 ${className}`}>
      <span aria-hidden className="sw-corner sw-corner--tl" />
      <span aria-hidden className="sw-corner sw-corner--tr" />
      <span aria-hidden className="sw-corner sw-corner--bl" />
      <span aria-hidden className="sw-corner sw-corner--br" />

      {title !== undefined && (
        <header className={showSystemTag ? "sw-header" : undefined}>
          <h1 className="font-display text-lg text-text-primary">{title}</h1>
        </header>
      )}

      <div className="mt-4">{children}</div>
    </section>
  );
}

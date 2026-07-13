"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { haptic } from "@/lib/haptics";

/** Utilitaires consultés rarement → barre du haut, toujours accessibles, sans
 * occuper un slot d'onglet au pouce (les onglets du bas restent réservés aux
 * boucles quotidiennes : Hub, Quêtes, Rituel). */
const ICONS = [
  {
    href: "/journal",
    label: "Journal",
    path: (
      <>
        <path d="M5 4h11l3 3v13H5z" />
        <path d="M8 10h8M8 14h6" />
      </>
    ),
  },
  {
    href: "/profil",
    label: "Profil",
    path: (
      <>
        <circle cx="12" cy="8" r="3.5" />
        <path d="M5 20c0-4 3.5-6 7-6s7 2 7 6" />
      </>
    ),
  },
  {
    href: "/reglages",
    label: "Réglages",
    path: (
      <>
        <circle cx="12" cy="12" r="3" />
        <path d="M12 3v2M12 19v2M3 12h2M19 12h2M6 6l1.5 1.5M16.5 16.5L18 18M18 6l-1.5 1.5M7.5 16.5L6 18" />
      </>
    ),
  },
];

export function TopBar() {
  const pathname = usePathname();

  return (
    <header className="topbar">
      <Link href="/" className="topbar__brand focus-ring" aria-label="Retour au Hub">
        <span className="clip-hex topbar__mark" aria-hidden />
        SYSTÈME
      </Link>

      <nav className="flex gap-1.5" aria-label="Utilitaires">
        {ICONS.map((it) => {
          const active = pathname === it.href;
          return (
            <Link
              key={it.href}
              href={it.href}
              aria-label={it.label}
              title={it.label}
              aria-current={active ? "page" : undefined}
              onClick={() => haptic("tap")}
              className="topbar__icon focus-ring"
            >
              <svg viewBox="0 0 24 24" aria-hidden>
                {it.path}
              </svg>
            </Link>
          );
        })}
      </nav>
    </header>
  );
}

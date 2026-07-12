"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

type Tab = {
  href: string;
  label: string;
  icon: React.ReactNode;
};

const TABS: Tab[] = [
  {
    href: "/",
    label: "Hub",
    icon: <path d="M12 3 L20 7.5 V16.5 L12 21 L4 16.5 V7.5 Z" />,
  },
  {
    href: "/quetes",
    label: "Quêtes",
    icon: (
      <>
        <path d="M14.5 4 L20 9.5 L10.5 19 L7.5 20 L5 17.5 L6 14.5 Z" />
        <path d="M5 17.5 L3 21" />
      </>
    ),
  },
  {
    href: "/rituel",
    label: "Rituel",
    icon: (
      <>
        <circle cx="12" cy="12" r="3.5" />
        <path d="M12 3 v2 M12 19 v2 M3 12 h2 M19 12 h2 M5.6 5.6 l1.4 1.4 M17 17 l1.4 1.4 M18.4 5.6 l-1.4 1.4 M7 17 l-1.4 1.4" />
      </>
    ),
  },
  {
    href: "/profil",
    label: "Profil",
    icon: (
      <>
        <circle cx="12" cy="8" r="3.6" />
        <path d="M5 20 C5 15.5 8.5 13.5 12 13.5 C15.5 13.5 19 15.5 19 20" />
      </>
    ),
  },
];

export function TabBar({ pendingCount = 0 }: { pendingCount?: number }) {
  const pathname = usePathname();

  return (
    <nav className="tabbar" aria-label="Navigation principale">
      {TABS.map((tab) => {
        const active = pathname === tab.href;
        const showBadge = tab.href === "/quetes" && pendingCount > 0;
        return (
          <Link
            key={tab.href}
            href={tab.href}
            className="tab focus-ring"
            aria-current={active ? "page" : undefined}
          >
            <span className="tab__hex clip-hex">
              <svg viewBox="0 0 24 24" aria-hidden>
                {tab.icon}
              </svg>
            </span>
            {tab.label}
            {showBadge && (
              <span className="tab__badge clip-hex-wide" aria-hidden>
                {pendingCount}
              </span>
            )}
          </Link>
        );
      })}
    </nav>
  );
}

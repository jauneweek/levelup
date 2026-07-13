"use client";

import { useEffect, useState, type ReactNode } from "react";
import { createPortal } from "react-dom";
import { haptic } from "@/lib/haptics";

/**
 * Modal « Fenêtre Système » (SPEC §9.2).
 *
 * ⚠️ Rendu via un PORTAL sur <body> — indispensable : la Fenêtre Système
 * utilise `backdrop-filter`, or filter/backdrop-filter créent un *containing
 * block* pour les descendants en `position: fixed`. Sans portal, le modal
 * restait piégé À L'INTÉRIEUR du panneau au lieu de couvrir l'écran.
 */
export function SystemModal({
  title,
  onClose,
  children,
}: {
  title: string;
  onClose: () => void;
  children: ReactNode;
}) {
  const [mounted, setMounted] = useState(false);

  useEffect(() => setMounted(true), []);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && onClose();
    window.addEventListener("keydown", onKey);
    const prev = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      window.removeEventListener("keydown", onKey);
      document.body.style.overflow = prev;
    };
  }, [onClose]);

  if (!mounted) return null;

  const close = () => {
    haptic("tap");
    onClose();
  };

  return createPortal(
    <div
      role="dialog"
      aria-modal="true"
      aria-label={title}
      onClick={close}
      className="fixed inset-0 z-[100] grid place-items-center p-4"
      style={{ background: "rgba(5,5,10,0.88)", backdropFilter: "blur(6px)" }}
    >
      <section
        onClick={(e) => e.stopPropagation()}
        className="system-window sw-enter thin-scroll w-full max-w-sm overflow-y-auto p-6"
        style={{ maxHeight: "84vh" }}
      >
        <span aria-hidden className="sw-corner sw-corner--tl" />
        <span aria-hidden className="sw-corner sw-corner--tr" />
        <span aria-hidden className="sw-corner sw-corner--bl" />
        <span aria-hidden className="sw-corner sw-corner--br" />

        <div className="flex items-start justify-between gap-3">
          <header className="sw-header">
            <h2 className="font-display text-lg text-text-primary">{title}</h2>
          </header>
          {/* Croix de fermeture — bien visible */}
          <button
            type="button"
            onClick={close}
            aria-label="Fermer"
            className="modal-close focus-ring"
          >
            ✕
          </button>
        </div>

        <div className="mt-5">{children}</div>
      </section>
    </div>,
    document.body,
  );
}

/** Jauge en hexagones (progression de quête, PV de boss). SPEC §9.2. */
export function Pips({
  filled,
  total,
  tone = "violet",
}: {
  filled: number;
  total: number;
  tone?: "violet" | "hp";
}) {
  return (
    <div className="flex flex-wrap gap-1.5" aria-label={`${filled} sur ${total}`}>
      {Array.from({ length: total }).map((_, i) => (
        <span
          key={i}
          className={`clip-hex pip ${tone === "hp" ? "pip--hp" : ""} ${
            i < filled ? "pip--full" : ""
          }`}
        />
      ))}
    </div>
  );
}

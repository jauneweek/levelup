import type { StatCode } from "@/lib/xp";
import { STAT_LABELS } from "@/lib/xp";

const inputClass =
  "w-full rounded border border-border-glow bg-black/30 px-3 py-2 text-sm text-text-primary placeholder:text-text-muted outline-none focus:border-cyan focus:ring-1 focus:ring-cyan";

const DAYS: { value: number; label: string }[] = [
  { value: 1, label: "Lun" },
  { value: 2, label: "Mar" },
  { value: 3, label: "Mer" },
  { value: 4, label: "Jeu" },
  { value: 5, label: "Ven" },
  { value: 6, label: "Sam" },
  { value: 7, label: "Dim" },
];

const STATS = Object.keys(STAT_LABELS) as StatCode[];

type HabitFormFieldsProps = {
  defaultValues?: {
    name?: string;
    stat?: StatCode;
    difficulty?: "easy" | "medium" | "hard";
    deadline_time?: string | null;
    minimal_version?: string | null;
    days?: number[];
  };
  idPrefix: string;
};

export function HabitFormFields({ defaultValues, idPrefix }: HabitFormFieldsProps) {
  const selectedDays = new Set(defaultValues?.days ?? [1, 2, 3, 4, 5, 6, 7]);

  return (
    <div className="space-y-3">
      <div className="space-y-1">
        <label htmlFor={`${idPrefix}-name`} className="text-xs text-text-muted">
          Nom de la quête
        </label>
        <input
          id={`${idPrefix}-name`}
          name="name"
          required
          defaultValue={defaultValues?.name}
          className={inputClass}
          placeholder="Ex. 30 min de lecture"
        />
      </div>

      <div className="grid grid-cols-2 gap-3">
        <div className="space-y-1">
          <label htmlFor={`${idPrefix}-stat`} className="text-xs text-text-muted">
            Statistique
          </label>
          <select
            id={`${idPrefix}-stat`}
            name="stat"
            defaultValue={defaultValues?.stat ?? "FOR"}
            className={inputClass}
          >
            {STATS.map((s) => (
              <option key={s} value={s}>
                {STAT_LABELS[s]}
              </option>
            ))}
          </select>
        </div>

        <div className="space-y-1">
          <label htmlFor={`${idPrefix}-difficulty`} className="text-xs text-text-muted">
            Difficulté
          </label>
          <select
            id={`${idPrefix}-difficulty`}
            name="difficulty"
            defaultValue={defaultValues?.difficulty ?? "easy"}
            className={inputClass}
          >
            <option value="easy">Facile · +10 XP</option>
            <option value="medium">Moyenne · +25 XP</option>
            <option value="hard">Difficile · +50 XP</option>
          </select>
        </div>
      </div>

      <div className="space-y-1">
        <label htmlFor={`${idPrefix}-deadline`} className="text-xs text-text-muted">
          Heure limite (optionnel)
        </label>
        <input
          id={`${idPrefix}-deadline`}
          type="time"
          name="deadline_time"
          defaultValue={defaultValues?.deadline_time ?? ""}
          className={inputClass}
        />
      </div>

      <div className="space-y-1">
        <label htmlFor={`${idPrefix}-minimal`} className="text-xs text-text-muted">
          Version minimale (donjon express, optionnel)
        </label>
        <input
          id={`${idPrefix}-minimal`}
          name="minimal_version"
          defaultValue={defaultValues?.minimal_version ?? ""}
          className={inputClass}
          placeholder="Ex. 2 pages, 5 pompes, 2 min de méditation"
        />
      </div>

      <div className="space-y-1">
        <span className="text-xs text-text-muted">Jours actifs</span>
        <div className="flex flex-wrap gap-2">
          {DAYS.map((d) => (
            <label
              key={d.value}
              className="flex items-center gap-1.5 rounded border border-border-glow px-2 py-1 text-xs text-text-muted has-[:checked]:border-cyan has-[:checked]:text-cyan"
            >
              <input
                type="checkbox"
                name="days"
                value={d.value}
                defaultChecked={selectedDays.has(d.value)}
                className="accent-cyan"
              />
              {d.label}
            </label>
          ))}
        </div>
      </div>
    </div>
  );
}

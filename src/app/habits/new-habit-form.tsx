"use client";

import { useRef } from "react";
import { HabitFormFields } from "./habit-form-fields";
import { createHabit } from "./actions";

export function NewHabitForm() {
  const formRef = useRef<HTMLFormElement>(null);

  return (
    <form
      ref={formRef}
      action={async (fd) => {
        await createHabit(fd);
        formRef.current?.reset();
      }}
    >
      <HabitFormFields idPrefix="new" />
      <button
        type="submit"
        className="mt-3 rounded bg-violet px-4 py-2 text-sm font-medium text-white hover:opacity-90"
      >
        Créer la quête
      </button>
    </form>
  );
}

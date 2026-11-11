import { type FormEvent, useState } from "react";

import { request } from "./api";

interface Suggestion {
  title: string;
  description: string;
}

// Kairos Assist: a note in, a task suggestion out (plan D-20, WP4.7). The suggestion is text the
// model wrote, so it is shown as text, never as markup (SV-12).
export function AssistPanel() {
  const [note, setNote] = useState("");
  const [suggestion, setSuggestion] = useState<Suggestion | null>(null);
  const [error, setError] = useState("");

  async function ask(event: FormEvent) {
    event.preventDefault();
    try {
      setSuggestion(
        await request<Suggestion>("/api/assist", { method: "POST", body: JSON.stringify({ note }) }),
      );
      setError("");
    } catch (problem) {
      setError(problem instanceof Error ? problem.message : "The assistant is unavailable");
    }
  }

  return (
    <section aria-label="Kairos Assist">
      <h2>Kairos Assist</h2>
      <form onSubmit={ask} aria-label="Ask the assistant">
        <input
          placeholder="Describe what you need to do"
          aria-label="Note for the assistant"
          value={note}
          onChange={(e) => setNote(e.target.value)}
          required
        />
        <button type="submit">Suggest a task</button>
      </form>
      {error && <p role="alert">{error}</p>}
      {suggestion && (
        <div data-testid="suggestion">
          <h3>{suggestion.title}</h3>
          {suggestion.description && <p>{suggestion.description}</p>}
        </div>
      )}
    </section>
  );
}

import { type FormEvent, useState } from "react";

import { request } from "./api";
import { AlertIcon } from "./Icons";

export interface Suggestion {
  title: string;
  description: string;
}

// Kairos Assist: a note in, a task suggestion out (plan D-20, WP4.7). The suggestion is text the
// model wrote, so it is shown as text, never as markup (SV-12). `onAdopt` turns it into a task of
// the person's own; without it the panel only suggests.
export function AssistPanel({ onAdopt }: { onAdopt?: (suggestion: Suggestion) => Promise<void> }) {
  const [note, setNote] = useState("");
  const [suggestion, setSuggestion] = useState<Suggestion | null>(null);
  const [error, setError] = useState("");
  const [asking, setAsking] = useState(false);
  const [adding, setAdding] = useState(false);

  async function ask(event: FormEvent) {
    event.preventDefault();
    setAsking(true);
    try {
      setSuggestion(
        await request<Suggestion>("/api/assist", { method: "POST", body: JSON.stringify({ note }) }),
      );
      setError("");
    } catch (problem) {
      setError(problem instanceof Error ? problem.message : "The assistant is unavailable.");
    } finally {
      setAsking(false);
    }
  }

  async function adopt() {
    if (!suggestion || !onAdopt) return;
    setAdding(true);
    try {
      await onAdopt(suggestion);
      setSuggestion(null);
      setNote("");
      setError("");
    } catch (problem) {
      setError(problem instanceof Error ? problem.message : "The task could not be added.");
    } finally {
      setAdding(false);
    }
  }

  return (
    <section className="assist" aria-label="Kairos Assist">
      <h2>Kairos Assist</h2>
      <form onSubmit={ask} aria-label="Ask the assistant">
        <input
          placeholder="Describe what you need to do"
          aria-label="Note for the assistant"
          value={note}
          maxLength={1000}
          onChange={(e) => setNote(e.target.value)}
          required
        />
        <button className="btn btn-primary btn-wide" type="submit" disabled={asking}>
          {asking ? "Suggesting…" : "Suggest a task"}
        </button>
      </form>
      {error && (
        <p className="alert alert-rail" role="alert">
          <AlertIcon />
          <span>{error}</span>
        </p>
      )}
      {suggestion && (
        <div className="suggestion" data-testid="suggestion">
          <h3>{suggestion.title}</h3>
          {suggestion.description && <p>{suggestion.description}</p>}
          {onAdopt && (
            <div className="suggestion-actions">
              <button className="btn btn-light btn-small" type="button" onClick={adopt} disabled={adding}>
                {adding ? "Adding…" : "Add to my tasks"}
              </button>
              <button className="btn btn-ghost btn-small" type="button" onClick={() => setSuggestion(null)}>
                Dismiss
              </button>
            </div>
          )}
        </div>
      )}
    </section>
  );
}

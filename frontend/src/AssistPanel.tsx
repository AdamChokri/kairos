import { type FormEvent, useState } from "react";

import { request } from "./api";

// Kairos Assist: a note in, a task suggestion out (plan D-20, WP4.7). First version: it works.
export function AssistPanel() {
  const [note, setNote] = useState("");
  const [suggestion, setSuggestion] = useState("");
  const [error, setError] = useState("");

  async function ask(event: FormEvent) {
    event.preventDefault();
    try {
      const answer = await request<{ suggestion: string }>("/api/assist", {
        method: "POST",
        body: JSON.stringify({ note }),
      });
      setSuggestion(answer.suggestion);
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
      {suggestion && <div data-testid="suggestion" dangerouslySetInnerHTML={{ __html: suggestion }} />}
    </section>
  );
}

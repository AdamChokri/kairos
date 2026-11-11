import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { App } from "./App";

// The call that starts the debounced search is marked `void` (SonarQube typescript:S9383, REL-01). That is
// only safe while a failed search becomes a message on the page: if it ever rejected, nothing would catch
// it, Vitest would report an unhandled rejection, and this run would fail.
beforeEach(() => localStorage.setItem("kairos_token", "abc"));
afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
  localStorage.clear();
});

describe("The task search", () => {
  it("asks the API for the typed text and shows an alert when the search fails", async () => {
    const fetchMock = vi.spyOn(globalThis, "fetch").mockImplementation(async (input) =>
      String(input).includes("search=")
        ? new Response(JSON.stringify({ detail: "The search is down" }), { status: 500 })
        : new Response(JSON.stringify([])),
    );
    render(<App />);
    fireEvent.change(await screen.findByLabelText("Search tasks"), { target: { value: "milk" } });

    expect(await screen.findByRole("alert", {}, { timeout: 2000 })).toBeTruthy();
    expect(fetchMock.mock.calls.some(([url]) => String(url).includes("search=milk"))).toBe(true);
  });
});

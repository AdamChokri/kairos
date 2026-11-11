import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";

import { AssistPanel } from "./AssistPanel";

afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
});

describe("Kairos Assist panel", () => {
  it("shows the assistant's suggestion", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(
      new Response(JSON.stringify({ suggestion: "Buy milk" })),
    );
    render(<AssistPanel />);
    fireEvent.change(screen.getByLabelText("Note for the assistant"), {
      target: { value: "milk" },
    });
    fireEvent.submit(screen.getByRole("form", { name: "Ask the assistant" }));
    expect(await screen.findByText("Buy milk")).toBeTruthy();
  });

  it("shows the API's message when the assistant is off", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(
      new Response(JSON.stringify({ detail: "Kairos Assist is switched off" }), { status: 404 }),
    );
    render(<AssistPanel />);
    fireEvent.change(screen.getByLabelText("Note for the assistant"), {
      target: { value: "milk" },
    });
    fireEvent.submit(screen.getByRole("form", { name: "Ask the assistant" }));
    expect((await screen.findByRole("alert")).textContent).toBe("Kairos Assist is switched off");
  });
});

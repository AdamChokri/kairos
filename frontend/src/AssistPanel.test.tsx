import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";

import { AssistPanel } from "./AssistPanel";

afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
});

function ask(answer: Response) {
  vi.spyOn(globalThis, "fetch").mockResolvedValue(answer);
  const view = render(<AssistPanel />);
  fireEvent.change(screen.getByLabelText("Note for the assistant"), { target: { value: "milk" } });
  fireEvent.submit(screen.getByRole("form", { name: "Ask the assistant" }));
  return view;
}

describe("Kairos Assist panel", () => {
  it("shows the suggested title and description", async () => {
    ask(new Response(JSON.stringify({ title: "Buy milk", description: "Two litres" })));
    expect(await screen.findByText("Buy milk")).toBeTruthy();
    expect(screen.getByText("Two litres")).toBeTruthy();
  });

  it("shows a suggestion that carries markup as inert text (SV-12)", async () => {
    document.title = "Kairos";
    const payload = `<img src=x onerror="document.title='XSS'">`;
    const { container } = ask(new Response(JSON.stringify({ title: payload, description: "" })));
    expect(await screen.findByText(payload)).toBeTruthy();
    expect(container.querySelector("img")).toBeNull();
    expect(document.title).toBe("Kairos");
  });

  it("shows the API's message when the assistant is off", async () => {
    ask(new Response(JSON.stringify({ detail: "Kairos Assist is switched off" }), { status: 404 }));
    expect((await screen.findByRole("alert")).textContent).toBe("Kairos Assist is switched off");
  });
});

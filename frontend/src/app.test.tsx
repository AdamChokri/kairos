import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { App } from "./App";
import { CommentList } from "./CommentList";

function answerWith(body: unknown, status = 200) {
  return vi
    .spyOn(globalThis, "fetch")
    .mockResolvedValue(new Response(JSON.stringify(body), { status }));
}

beforeEach(() => localStorage.clear());
afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
});

describe("Kairos", () => {
  it("shows the log-in form to a visitor without a token", () => {
    render(<App />);
    expect(screen.getByRole("form", { name: "Log in" })).toBeTruthy();
  });

  it("logs in, keeps the token and shows the task list", async () => {
    const fetchMock = vi
      .spyOn(globalThis, "fetch")
      .mockResolvedValueOnce(new Response(JSON.stringify({ access_token: "abc" })))
      .mockResolvedValue(
        new Response(
          JSON.stringify([{ id: 1, title: "Buy milk", description: "", done: false, owner_id: 1 }]),
        ),
      );
    render(<App />);
    fireEvent.change(screen.getByLabelText("Username"), { target: { value: "alice" } });
    fireEvent.change(screen.getByLabelText("Password"), { target: { value: "correct-horse-1" } });
    fireEvent.submit(screen.getByRole("form", { name: "Log in" }));

    expect(await screen.findByText("Buy milk")).toBeTruthy();
    expect(localStorage.getItem("kairos_token")).toBe("abc");
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it("shows the API's message when the log-in is refused", async () => {
    answerWith({ detail: "Invalid credentials" }, 401);
    render(<App />);
    fireEvent.change(screen.getByLabelText("Username"), { target: { value: "alice" } });
    fireEvent.change(screen.getByLabelText("Password"), { target: { value: "wrong-pass-99" } });
    fireEvent.submit(screen.getByRole("form", { name: "Log in" }));
    await waitFor(() => expect(screen.getByRole("alert").textContent).toBe("Invalid credentials"));
  });

  it("lists the comments of a task", () => {
    render(
      <CommentList
        comments={[{ id: 1, task_id: 1, author_id: 1, body: "Looks good", created_at: "" }]}
      />,
    );
    expect(screen.getByText("Looks good")).toBeTruthy();
  });
});

import { cleanup, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { App } from "./App";
import { formatTime } from "./format";

// The interface of WP: UI-01 (the Graphite design). The API is a stub that answers by method and path, so what is
// tested is what the person sees and what is sent, not the server.
type Handler = (init: RequestInit | undefined) => Response | Promise<Response>;

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status });
const task = (id: number, title: string, done = false, description = "") => ({
  id,
  title,
  description,
  done,
  owner_id: 1,
});

function serve(routes: Record<string, Handler>) {
  const calls: { method: string; path: string; body: string }[] = [];
  vi.spyOn(globalThis, "fetch").mockImplementation(async (input, init) => {
    const url = new URL(String(input));
    const method = init?.method ?? "GET";
    const path = url.pathname + url.search;
    calls.push({ method, path, body: String(init?.body ?? "") });
    const handler = routes[`${method} ${path}`];
    return handler ? handler(init) : json({ detail: `unexpected ${method} ${path}` }, 500);
  });
  return calls;
}

beforeEach(() => {
  localStorage.clear();
  localStorage.setItem("kairos_token", "token");
  window.location.hash = "";
});
afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
});

describe("the task list", () => {
  it("groups the tasks into open and done and counts each group", async () => {
    serve({ "GET /api/tasks": () => json([task(1, "Book the room"), task(2, "Order monitors", true), task(3, "Renew passport")]) });
    render(<App />);

    expect(await screen.findByRole("heading", { name: "Open 2" })).toBeTruthy();
    expect(screen.getByRole("heading", { name: "Done 1" })).toBeTruthy();
    const links = within(screen.getByRole("navigation", { name: "Tasks" })).getAllByRole("link");
    expect(links.map((link) => link.textContent)).toEqual(["Book the room", "Renew passport", "Order monitors (done)"]);
  });

  it("marks the open task with aria-current", async () => {
    window.location.hash = "#/tasks/3";
    serve({
      "GET /api/tasks": () => json([task(1, "Book the room"), task(3, "Renew passport")]),
      "GET /api/tasks/3": () => json(task(3, "Renew passport")),
      "GET /api/tasks/3/comments": () => json([]),
    });
    render(<App />);

    expect(await screen.findByRole("heading", { level: 1, name: "Renew passport" })).toBeTruthy();
    const current = screen.getByRole("link", { current: "page" });
    expect(current.textContent).toBe("Renew passport");
  });

  it("says what to do when there are no tasks", async () => {
    serve({ "GET /api/tasks": () => json([]) });
    render(<App />);

    expect(await screen.findByText(/No tasks yet\./)).toBeTruthy();
    expect(screen.getByText("You have no tasks yet.")).toBeTruthy();
  });

  it("says so when a search finds nothing", async () => {
    serve({ "GET /api/tasks": () => json([task(1, "Book the room")]), "GET /api/tasks?search=zebra": () => json([]) });
    render(<App />);
    await screen.findByText("Book the room");

    fireEvent.change(screen.getByLabelText("Search tasks"), { target: { value: "zebra" } });
    expect(await screen.findByText("No task matches “zebra”.")).toBeTruthy();
  });

  it("shows why the list is missing, with a way to try again", async () => {
    let answered = 0;
    serve({
      "GET /api/tasks": () => (++answered === 1 ? json({ detail: "Internal Server Error" }, 500) : json([task(1, "Book the room")])),
    });
    render(<App />);

    expect((await screen.findByRole("alert")).textContent).toContain("The server had a problem. Try again in a moment.");
    fireEvent.click(screen.getByRole("button", { name: "Try again" }));
    expect(await screen.findByText("Book the room")).toBeTruthy();
  });

  it("adds a task from the New task form and shows it", async () => {
    let tasks = [task(1, "Book the room")];
    const calls = serve({
      "GET /api/tasks": () => json(tasks),
      "POST /api/tasks": (init) => {
        const sent = JSON.parse(String(init?.body));
        tasks = [...tasks, task(2, sent.title)];
        return json(tasks[1], 201);
      },
    });
    render(<App />);
    await screen.findByText("Book the room");

    fireEvent.click(screen.getByRole("button", { name: "New task" }));
    fireEvent.change(screen.getByLabelText("New task title"), { target: { value: "Pay the invoice" } });
    fireEvent.submit(screen.getByRole("form", { name: "New task" }));

    expect(await screen.findByText("Pay the invoice")).toBeTruthy();
    expect(calls.find((call) => call.method === "POST")?.body).toBe(JSON.stringify({ title: "Pay the invoice", description: "" }));
    expect(screen.queryByRole("form", { name: "New task" })).toBeNull();
  });

  it("puts the focus in the title field when the New task form opens", async () => {
    serve({ "GET /api/tasks": () => json([task(1, "Book the room")]) });
    render(<App />);
    await screen.findByText("Book the room");

    fireEvent.click(screen.getByRole("button", { name: "New task" }));

    expect(document.activeElement).toBe(screen.getByLabelText("New task title"));
  });
});

describe("a task", () => {
  const open = (extra: Record<string, Handler> = {}) => {
    window.location.hash = "#/tasks/7";
    return serve({
      "GET /api/tasks": () => json([task(7, "Prepare the workshop", false, "Agenda and room.")]),
      "GET /api/tasks/7": () => json(task(7, "Prepare the workshop", false, "Agenda and room.")),
      "GET /api/tasks/7/comments": () => json([]),
      ...extra,
    });
  };

  it("shows its description, its status and an empty comment list", async () => {
    open();
    render(<App />);

    expect(await screen.findByRole("heading", { level: 1, name: "Prepare the workshop" })).toBeTruthy();
    expect(screen.getByText("Agenda and room.")).toBeTruthy();
    expect(screen.getByText("Open", { selector: ".status" })).toBeTruthy();
    expect(screen.getByText("No comments yet.")).toBeTruthy();
  });

  it("asks before it deletes, and deletes only after the confirmation", async () => {
    const calls = open({ "DELETE /api/tasks/7": () => new Response(null, { status: 204 }) });
    render(<App />);
    await screen.findByRole("heading", { level: 1, name: "Prepare the workshop" });

    fireEvent.click(screen.getByRole("button", { name: "Delete task" }));
    expect(screen.getByText(/Delete this task and its comments\?/)).toBeTruthy();
    expect(calls.some((call) => call.method === "DELETE")).toBe(false);

    fireEvent.click(screen.getByRole("button", { name: "Keep it" }));
    expect(screen.queryByText(/Delete this task and its comments\?/)).toBeNull();
    expect(calls.some((call) => call.method === "DELETE")).toBe(false);

    fireEvent.click(screen.getByRole("button", { name: "Delete task" }));
    fireEvent.click(within(screen.getByRole("group", { name: "Confirm delete" })).getByRole("button", { name: "Delete task" }));
    await waitFor(() => expect(calls.some((call) => call.method === "DELETE")).toBe(true));
    await waitFor(() => expect(window.location.hash).toBe("#/"));
  });

  it("marks a task as done and sends the whole task back", async () => {
    const calls = open({
      "PUT /api/tasks/7": () => json(task(7, "Prepare the workshop", true, "Agenda and room.")),
    });
    render(<App />);
    await screen.findByRole("heading", { level: 1, name: "Prepare the workshop" });

    fireEvent.click(screen.getByRole("button", { name: "Mark as done" }));
    expect(await screen.findByRole("button", { name: "Mark as open" })).toBeTruthy();
    expect(calls.find((call) => call.method === "PUT")?.body).toBe(
      JSON.stringify({ title: "Prepare the workshop", description: "Agenda and room.", done: true }),
    );
  });

  it("shows the API's message when the task does not exist", async () => {
    window.location.hash = "#/tasks/99";
    serve({
      "GET /api/tasks": () => json([]),
      "GET /api/tasks/99": () => json({ detail: "Task not found" }, 404),
    });
    render(<App />);

    expect((await screen.findByRole("alert")).textContent).toBe("Task not found");
    expect(screen.getByRole("link", { name: "All tasks" })).toBeTruthy();
  });

  it("adds a comment and shows it with its time", async () => {
    let comments: unknown[] = [];
    const calls = open({
      "GET /api/tasks/7/comments": () => json(comments),
      "POST /api/tasks/7/comments": () => {
        comments = [{ id: 1, task_id: 7, author_id: 1, body: "Room 2.04 is free", created_at: "2026-11-09T10:00:00" }];
        return json(comments[0], 201);
      },
    });
    const { container } = render(<App />);
    await screen.findByRole("heading", { level: 1, name: "Prepare the workshop" });

    fireEvent.change(screen.getByLabelText("Comment text"), { target: { value: "Room 2.04 is free" } });
    fireEvent.submit(screen.getByRole("form", { name: "New comment" }));

    expect(await screen.findByText("Room 2.04 is free")).toBeTruthy();
    expect(calls.find((call) => call.method === "POST")?.body).toBe(JSON.stringify({ body: "Room 2.04 is free" }));
    expect(container.querySelector("time")?.textContent).toMatch(/^9 Nov, \d{2}:\d{2}$/);
    expect((screen.getByLabelText("Comment text") as HTMLTextAreaElement).value).toBe("");
  });

  it("shows why a comment was not added, and keeps what was typed", async () => {
    open({ "POST /api/tasks/7/comments": () => json({ detail: "Too many comments" }, 429) });
    render(<App />);
    await screen.findByRole("heading", { level: 1, name: "Prepare the workshop" });

    fireEvent.change(screen.getByLabelText("Comment text"), { target: { value: "Hello" } });
    fireEvent.submit(screen.getByRole("form", { name: "New comment" }));

    expect((await screen.findByRole("alert")).textContent).toBe("Too many comments");
    expect((screen.getByLabelText("Comment text") as HTMLTextAreaElement).value).toBe("Hello");
  });
});

describe("Kairos Assist in the workspace", () => {
  it("adds the suggestion to the person's tasks and opens the new task", async () => {
    let tasks: unknown[] = [];
    const calls = serve({
      "GET /api/tasks": () => json(tasks),
      "POST /api/assist": () => json({ title: "Prepare the client workshop", description: "Agenda, slides and the room." }),
      "POST /api/tasks": () => {
        tasks = [task(9, "Prepare the client workshop", false, "Agenda, slides and the room.")];
        return json(tasks[0], 201);
      },
    });
    render(<App />);
    await screen.findByText(/No tasks yet\./);

    fireEvent.change(screen.getByLabelText("Note for the assistant"), { target: { value: "client workshop on Thursday" } });
    fireEvent.submit(screen.getByRole("form", { name: "Ask the assistant" }));
    fireEvent.click(await screen.findByRole("button", { name: "Add to my tasks" }));

    await waitFor(() => expect(window.location.hash).toBe("#/tasks/9"));
    expect(calls.find((call) => call.path === "/api/tasks" && call.method === "POST")?.body).toBe(
      JSON.stringify({ title: "Prepare the client workshop", description: "Agenda, slides and the room." }),
    );
    expect(screen.queryByTestId("suggestion")).toBeNull();
  });

  it("lets the person dismiss a suggestion", async () => {
    const calls = serve({
      "GET /api/tasks": () => json([]),
      "POST /api/assist": () => json({ title: "Call the bank", description: "" }),
    });
    render(<App />);
    await screen.findByText(/No tasks yet\./);

    fireEvent.change(screen.getByLabelText("Note for the assistant"), { target: { value: "bank" } });
    fireEvent.submit(screen.getByRole("form", { name: "Ask the assistant" }));
    await screen.findByText("Call the bank");
    fireEvent.click(screen.getByRole("button", { name: "Dismiss" }));

    expect(screen.queryByText("Call the bank")).toBeNull();
    expect(calls.some((call) => call.path === "/api/tasks" && call.method === "POST")).toBe(false);
  });
});

describe("the session", () => {
  it("returns to the log-in form, with the reason, when the API refuses the token", async () => {
    serve({ "GET /api/tasks": () => json({ detail: "Could not validate credentials" }, 401) });
    render(<App />);

    expect(await screen.findByRole("form", { name: "Log in" })).toBeTruthy();
    expect(screen.getByRole("status").textContent).toBe("Your session has ended. Log in again.");
    expect(localStorage.getItem("kairos_token")).toBeNull();
  });

  it("forgets the open task when the person logs out", async () => {
    window.location.hash = "#/tasks/7";
    serve({
      "GET /api/tasks": () => json([]),
      "GET /api/tasks/7": () => json(task(7, "Prepare the workshop")),
      "GET /api/tasks/7/comments": () => json([]),
    });
    render(<App />);
    await screen.findByRole("heading", { level: 1, name: "Prepare the workshop" });

    fireEvent.click(screen.getByRole("button", { name: "Log out" }));
    expect(screen.getByRole("form", { name: "Log in" })).toBeTruthy();
    expect(window.location.hash).toBe("");
    expect(localStorage.getItem("kairos_token")).toBeNull();
  });
});

describe("formatTime", () => {
  it("reads a time without a zone as UTC, like the API means it", () => {
    expect(formatTime("2026-11-09T10:00:00")).toBe(formatTime("2026-11-09T10:00:00Z"));
    expect(formatTime("2026-11-09T10:00:00.123456")).toBe(formatTime("2026-11-09T10:00:00.123456Z"));
    expect(formatTime("2026-11-09T10:00:00+01:00")).toBe(formatTime("2026-11-09T09:00:00Z"));
  });

  it("shows nothing for a time it cannot read", () => {
    expect(formatTime("")).toBe("");
    expect(formatTime("not a date")).toBe("");
  });
});

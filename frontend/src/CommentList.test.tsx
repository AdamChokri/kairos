import { cleanup, render } from "@testing-library/react";
import { afterEach, describe, expect, it } from "vitest";

import type { Comment } from "./api";
import { CommentList } from "./CommentList";

afterEach(() => {
  cleanup();
  delete (globalThis as { __xss?: number }).__xss;
});

function comment(id: number, body: string): Comment {
  return { id, task_id: 1, author_id: 1, body, created_at: "2026-11-09T10:00:00Z" };
}

// SV-03 (and SV-12 for the assistant): the text of a comment is shown as text, never as markup.
describe("CommentList", () => {
  it("shows a comment's markup as inert text", () => {
    const payload = '<img src=x onerror="globalThis.__xss=1">';
    const { container } = render(<CommentList comments={[comment(1, payload)]} />);

    expect(container.querySelector("img")).toBeNull();
    expect(container.querySelector("[onerror]")).toBeNull();
    expect(container.textContent).toBe(payload);
    expect((globalThis as { __xss?: number }).__xss).toBeUndefined();
  });

  it("does not create a script, a link or a frame from a comment", () => {
    const body = '<script>globalThis.__xss=1</script><a href="javascript:1">x</a><iframe src="//e"></iframe>';
    const { container } = render(<CommentList comments={[comment(2, body)]} />);

    expect(container.querySelector("script, a, iframe")).toBeNull();
    expect(container.textContent).toBe(body);
  });

  it("still shows an ordinary comment, one list item each", () => {
    const { container } = render(
      <CommentList comments={[comment(3, "Call the bank"), comment(4, "Done & dusted")]} />,
    );

    const items = Array.from(container.querySelectorAll("li")).map((li) => li.textContent);
    expect(items).toEqual(["Call the bank", "Done & dusted"]);
  });
});

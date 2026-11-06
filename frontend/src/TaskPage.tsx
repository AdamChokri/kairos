import { type FormEvent, useCallback, useEffect, useState } from "react";

import { type Comment, type Task, request } from "./api";
import { CommentList } from "./CommentList";

export function TaskPage({ id }: { id: number }) {
  const [task, setTask] = useState<Task | null>(null);
  const [comments, setComments] = useState<Comment[]>([]);
  const [body, setBody] = useState("");
  const [error, setError] = useState("");

  const load = useCallback(async () => {
    try {
      setTask(await request<Task>(`/api/tasks/${id}`));
      setComments(await request<Comment[]>(`/api/tasks/${id}/comments`));
      setError("");
    } catch (problem) {
      setError(problem instanceof Error ? problem.message : "Could not load the task");
    }
  }, [id]);

  useEffect(() => {
    void load();
  }, [load]);

  async function toggleDone() {
    if (!task) return;
    const { title, description, done } = task;
    setTask(
      await request<Task>(`/api/tasks/${id}`, {
        method: "PUT",
        body: JSON.stringify({ title, description, done: !done }),
      }),
    );
  }

  async function remove() {
    await request(`/api/tasks/${id}`, { method: "DELETE" });
    window.location.hash = "#/";
  }

  async function addComment(event: FormEvent) {
    event.preventDefault();
    await request<Comment>(`/api/tasks/${id}/comments`, {
      method: "POST",
      body: JSON.stringify({ body }),
    });
    setBody("");
    await load();
  }

  if (error) return <p role="alert">{error}</p>;
  if (!task) return <p>Loading…</p>;

  return (
    <section>
      <p>
        <a href="#/">← All tasks</a>
      </p>
      <h2>{task.title}</h2>
      <p>{task.description}</p>
      <button type="button" onClick={toggleDone}>
        {task.done ? "Mark as open" : "Mark as done"}
      </button>
      <button type="button" onClick={remove}>
        Delete
      </button>
      <h3>Comments</h3>
      <CommentList comments={comments} />
      <form onSubmit={addComment} aria-label="New comment">
        <textarea
          aria-label="Comment text"
          value={body}
          onChange={(e) => setBody(e.target.value)}
          required
        />
        <button type="submit">Comment</button>
      </form>
    </section>
  );
}

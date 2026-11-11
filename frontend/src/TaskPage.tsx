import { type FormEvent, useCallback, useEffect, useRef, useState } from "react";

import { type Comment, type Task, request } from "./api";
import { CommentList } from "./CommentList";
import { AlertIcon, BackIcon } from "./Icons";

export function TaskPage({ id, onChanged }: { id: number; onChanged: () => void }) {
  const [task, setTask] = useState<Task | null>(null);
  const [comments, setComments] = useState<Comment[]>([]);
  const [body, setBody] = useState("");
  const [loadError, setLoadError] = useState("");
  const [actionError, setActionError] = useState("");
  const [confirming, setConfirming] = useState(false);
  const [busy, setBusy] = useState(false);
  const keepRef = useRef<HTMLButtonElement>(null);
  const deleteRef = useRef<HTMLButtonElement>(null);
  const wasConfirming = useRef(false);

  // The question replaces the buttons, so the keyboard follows it: to "Keep it" (the safe answer) when it opens, and
  // back to "Delete task" when it is answered "keep".
  useEffect(() => {
    if (confirming) keepRef.current?.focus();
    else if (wasConfirming.current) deleteRef.current?.focus();
    wasConfirming.current = confirming;
  }, [confirming]);

  const load = useCallback(async () => {
    try {
      setTask(await request<Task>(`/api/tasks/${id}`));
      setComments(await request<Comment[]>(`/api/tasks/${id}/comments`));
      setLoadError("");
    } catch (problem) {
      setLoadError(problem instanceof Error ? problem.message : "Could not load the task.");
    }
  }, [id]);

  useEffect(() => {
    void load();
  }, [load]);

  // Runs one change; a failure is shown above the buttons and the page stays as it was.
  async function act(change: () => Promise<void>, failure: string) {
    setBusy(true);
    setActionError("");
    try {
      await change();
    } catch (problem) {
      setActionError(problem instanceof Error ? problem.message : failure);
    } finally {
      setBusy(false);
    }
  }

  function toggleDone() {
    if (!task) return;
    const { title, description, done } = task;
    void act(async () => {
      setTask(
        await request<Task>(`/api/tasks/${id}`, {
          method: "PUT",
          body: JSON.stringify({ title, description, done: !done }),
        }),
      );
      onChanged();
    }, "The task could not be updated.");
  }

  function remove() {
    void act(async () => {
      await request(`/api/tasks/${id}`, { method: "DELETE" });
      onChanged();
      window.location.hash = "#/";
    }, "The task could not be deleted.");
  }

  async function addComment(event: FormEvent) {
    event.preventDefault();
    await act(async () => {
      await request<Comment>(`/api/tasks/${id}/comments`, {
        method: "POST",
        body: JSON.stringify({ body }),
      });
      setBody("");
      await load();
    }, "The comment could not be added.");
  }

  const back = (
    <a className="back-link" href="#/">
      <BackIcon />
      All tasks
    </a>
  );

  if (loadError) {
    return (
      <div className="page">
        {back}
        <p className="alert" role="alert">
          <AlertIcon />
          <span>{loadError}</span>
        </p>
      </div>
    );
  }
  if (!task) {
    return (
      <div className="page">
        {back}
        <p className="lede" role="status">
          Loading the task…
        </p>
      </div>
    );
  }

  return (
    <article className="page">
      {back}
      <p className={`status${task.done ? " is-done" : ""}`}>
        <span className="status-dot" aria-hidden="true" />
        {task.done ? "Done" : "Open"}
      </p>
      <h1>{task.title}</h1>
      {task.description ? (
        <p className="description">{task.description}</p>
      ) : (
        <p className="description is-empty">No description.</p>
      )}

      {actionError && (
        <p className="alert" role="alert">
          <AlertIcon />
          <span>{actionError}</span>
        </p>
      )}
      {confirming ? (
        <div className="actions confirm" role="group" aria-label="Confirm delete">
          <p>Delete this task and its comments? This cannot be undone.</p>
          <button className="btn btn-danger" type="button" onClick={remove} disabled={busy}>
            Delete task
          </button>
          <button ref={keepRef} className="btn btn-ghost" type="button" onClick={() => setConfirming(false)}>
            Keep it
          </button>
        </div>
      ) : (
        <div className="actions">
          <button className="btn btn-primary" type="button" onClick={toggleDone} disabled={busy}>
            {task.done ? "Mark as open" : "Mark as done"}
          </button>
          <button ref={deleteRef} className="btn btn-ghost" type="button" onClick={() => setConfirming(true)}>
            Delete task
          </button>
        </div>
      )}

      <section className="comments-block" aria-labelledby="comments-title">
        <h2 id="comments-title">
          Comments{" "}
          <span className="count">{comments.length}</span>
        </h2>
        {comments.length === 0 ? <p className="quiet">No comments yet.</p> : <CommentList comments={comments} />}
        <form className="comment-form" onSubmit={addComment} aria-label="New comment">
          <textarea
            aria-label="Comment text"
            placeholder="Write a comment"
            value={body}
            maxLength={2000}
            rows={3}
            onChange={(e) => setBody(e.target.value)}
            required
          />
          <button className="btn btn-secondary" type="submit" disabled={busy}>
            Comment
          </button>
        </form>
      </section>
    </article>
  );
}

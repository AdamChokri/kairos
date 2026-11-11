import { type FormEvent, useState } from "react";

import type { Task } from "./api";
import { AlertIcon, SearchIcon } from "./Icons";

interface Props {
  tasks: Task[];
  selectedId: number | null;
  state: "loading" | "ready" | "failed";
  error: string;
  search: string;
  onSearch: (text: string) => void;
  onAdd: (title: string) => Promise<void>;
  onRetry: () => void;
}

function Group({ title, tasks, selectedId }: { title: string; tasks: Task[]; selectedId: number | null }) {
  if (tasks.length === 0) return null;
  return (
    <section>
      <h2 className="group-title">
        {title}{" "}
        <span className="count">{tasks.length}</span>
      </h2>
      <ul className="tasks">
        {tasks.map((task) => (
          <li key={task.id}>
            <a
              className={`task-link${task.done ? " is-done" : ""}`}
              href={`#/tasks/${task.id}`}
              aria-current={task.id === selectedId ? "page" : undefined}
            >
              <span className="task-dot" aria-hidden="true" />
              <span className="task-title">{task.title}</span>
              {task.done && <span className="visually-hidden"> (done)</span>}
            </a>
          </li>
        ))}
      </ul>
    </section>
  );
}

export function TaskList({ tasks, selectedId, state, error, search, onSearch, onAdd, onRetry }: Props) {
  const [adding, setAdding] = useState(false);
  const [title, setTitle] = useState("");
  const [addError, setAddError] = useState("");
  const [busy, setBusy] = useState(false);

  async function create(event: FormEvent) {
    event.preventDefault();
    setBusy(true);
    setAddError("");
    try {
      await onAdd(title.trim());
      setTitle("");
      setAdding(false);
    } catch (problem) {
      setAddError(problem instanceof Error ? problem.message : "The task could not be added.");
    } finally {
      setBusy(false);
    }
  }

  function closeForm() {
    setAdding(false);
    setTitle("");
    setAddError("");
  }

  const open = tasks.filter((task) => !task.done);
  const done = tasks.filter((task) => task.done);

  return (
    <>
      <div className="search">
        <SearchIcon />
        <input
          type="search"
          placeholder="Search tasks"
          aria-label="Search tasks"
          value={search}
          onChange={(e) => onSearch(e.target.value)}
        />
      </div>

      <nav className="rail-list" aria-label="Tasks">
        {!adding && (
          <button className="new-task" type="button" onClick={() => setAdding(true)}>
            <span className="new-task-plus" aria-hidden="true" />
            New task
          </button>
        )}

        {adding && (
          <form className="add-form" onSubmit={create} aria-label="New task">
            <input
              placeholder="What needs doing?"
              aria-label="New task title"
              value={title}
              maxLength={200}
              onChange={(e) => setTitle(e.target.value)}
              onKeyDown={(e) => e.key === "Escape" && closeForm()}
              autoFocus
              required
            />
            <div className="add-actions">
              <button className="btn btn-primary btn-small" type="submit" disabled={busy}>
                {busy ? "Adding…" : "Add"}
              </button>
              <button className="btn btn-ghost btn-small" type="button" onClick={closeForm}>
                Cancel
              </button>
            </div>
            {addError && (
              <p className="alert alert-rail" role="alert">
                <AlertIcon />
                <span>{addError}</span>
              </p>
            )}
          </form>
        )}

        {state === "loading" && (
          <p className="rail-note" role="status">
            Loading your tasks…
          </p>
        )}
        {state === "failed" && (
          <div className="alert alert-rail" role="alert">
            <AlertIcon />
            <div>
              <span>{error}</span>
              <button className="btn-inline" type="button" onClick={onRetry}>
                Try again
              </button>
            </div>
          </div>
        )}
        {state === "ready" && tasks.length === 0 && (
          <p className="rail-note">
            {search ? `No task matches “${search}”.` : "No tasks yet."}
          </p>
        )}

        <Group title="Open" tasks={open} selectedId={selectedId} />
        <Group title="Done" tasks={done} selectedId={selectedId} />
      </nav>
    </>
  );
}

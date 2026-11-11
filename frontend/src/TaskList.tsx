import debounce from "lodash/debounce";
import { type FormEvent, useCallback, useEffect, useMemo, useState } from "react";

import { type Task, request } from "./api";

export function TaskList() {
  const [tasks, setTasks] = useState<Task[]>([]);
  const [search, setSearch] = useState("");
  const [title, setTitle] = useState("");
  const [error, setError] = useState("");

  const load = useCallback(async (text: string) => {
    try {
      const query = text ? `?search=${encodeURIComponent(text)}` : "";
      setTasks(await request<Task[]>(`/api/tasks${query}`));
      setError("");
    } catch (problem) {
      setError(problem instanceof Error ? problem.message : "Could not load the tasks");
    }
  }, []);

  // The search runs 300 ms after the last key press.
  const searchLater = useMemo(() => debounce(load, 300), [load]);

  useEffect(() => {
    void load("");
  }, [load]);

  useEffect(() => () => searchLater.cancel(), [searchLater]);

  async function create(event: FormEvent) {
    event.preventDefault();
    await request<Task>("/api/tasks", { method: "POST", body: JSON.stringify({ title }) });
    setTitle("");
    await load(search);
  }

  return (
    <section>
      <h2>Tasks</h2>
      <input
        type="search"
        placeholder="Search tasks"
        aria-label="Search tasks"
        value={search}
        onChange={(e) => {
          setSearch(e.target.value);
          void searchLater(e.target.value);
        }}
      />
      <form onSubmit={create} aria-label="New task">
        <input
          placeholder="New task"
          aria-label="New task title"
          value={title}
          onChange={(e) => setTitle(e.target.value)}
          required
        />
        <button type="submit">Add</button>
      </form>
      {error && <p role="alert">{error}</p>}
      <ul>
        {tasks.map((task) => (
          <li key={task.id}>
            <a href={`#/tasks/${task.id}`}>{task.title}</a>
            {task.done ? " (done)" : ""}
          </li>
        ))}
      </ul>
    </section>
  );
}

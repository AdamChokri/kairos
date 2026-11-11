import debounce from "lodash/debounce";
import { useCallback, useEffect, useMemo, useState } from "react";

import { type Task, request } from "./api";
import { AssistPanel, type Suggestion } from "./AssistPanel";
import { Mark } from "./Icons";
import { Overview } from "./Overview";
import { TaskList } from "./TaskList";
import { TaskPage } from "./TaskPage";

// The signed-in screen: the dark rail (the tasks, then Kairos Assist) and the task that is open beside it. The tasks
// are loaded here, once, so that what a task page changes (done, deleted) shows in the rail at the same moment.
export function Workspace({ taskId, onLogout }: { taskId: number | null; onLogout: () => void }) {
  const [tasks, setTasks] = useState<Task[]>([]);
  const [search, setSearch] = useState("");
  const [state, setState] = useState<"loading" | "ready" | "failed">("loading");
  const [error, setError] = useState("");

  const load = useCallback(async (text: string) => {
    try {
      const query = text ? `?search=${encodeURIComponent(text)}` : "";
      setTasks(await request<Task[]>(`/api/tasks${query}`));
      setState("ready");
      setError("");
    } catch (problem) {
      setState("failed");
      setError(problem instanceof Error ? problem.message : "Could not load the tasks.");
    }
  }, []);

  // The search runs 300 ms after the last key press.
  const searchLater = useMemo(() => debounce(load, 300), [load]);

  useEffect(() => {
    void load("");
  }, [load]);

  useEffect(() => () => searchLater.cancel(), [searchLater]);

  function onSearch(text: string) {
    setSearch(text);
    void searchLater(text);
  }

  async function addTask(title: string, description = ""): Promise<Task> {
    const task = await request<Task>("/api/tasks", {
      method: "POST",
      body: JSON.stringify({ title, description }),
    });
    await load(search);
    return task;
  }

  async function adopt(suggestion: Suggestion) {
    const task = await addTask(suggestion.title, suggestion.description);
    window.location.hash = `#/tasks/${task.id}`;
  }

  return (
    <div className="workspace" data-view={taskId === null ? "list" : "task"}>
      <aside className="rail">
        <div className="rail-top">
          <div className="wordmark">
            <Mark size={22} />
            <span>Kairos</span>
          </div>
          <button className="rail-logout" type="button" onClick={onLogout}>
            Log out
          </button>
        </div>
        <TaskList
          tasks={tasks}
          selectedId={taskId}
          state={state}
          error={error}
          search={search}
          onSearch={onSearch}
          onAdd={async (title) => {
            await addTask(title);
          }}
          onRetry={() => void load(search)}
        />
        <AssistPanel onAdopt={adopt} />
      </aside>
      <main className="stage">
        {taskId === null ? (
          <Overview tasks={tasks} state={state} searching={search !== ""} />
        ) : (
          <TaskPage key={taskId} id={taskId} onChanged={() => void load(search)} />
        )}
      </main>
    </div>
  );
}

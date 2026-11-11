import type { Task } from "./api";

// What the right-hand side shows when no task is open: where things are, and what to do next.
export function Overview({
  tasks,
  state,
  searching,
}: {
  tasks: Task[];
  state: "loading" | "ready" | "failed";
  searching: boolean;
}) {
  const open = tasks.filter((task) => !task.done).length;
  const done = tasks.length - open;

  let summary = "";
  if (state === "failed") summary = "Your tasks could not be loaded.";
  if (state === "ready") {
    if (tasks.length === 0) summary = searching ? "No task matches that search." : "You have no tasks yet.";
    else summary = `${open} open, ${done} done${searching ? " in this search" : ""}.`;
  }

  return (
    <div className="page overview">
      <h1>Your tasks</h1>
      <p className="lede">{summary}</p>
      {state === "ready" && tasks.length === 0 && !searching ? (
        <ul className="hints">
          <li>Choose New task to add one yourself.</li>
          <li>Or describe what you need to Kairos Assist, and add its suggestion to your tasks.</li>
        </ul>
      ) : (
        state === "ready" && <p className="hint">Open a task from the list to read it, mark it done or comment on it.</p>
      )}
    </div>
  );
}

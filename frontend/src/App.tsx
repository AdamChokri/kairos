import { useEffect, useState } from "react";

import { clearToken, getToken } from "./api";
import { Login } from "./Login";
import { TaskList } from "./TaskList";
import { TaskPage } from "./TaskPage";

function currentTaskId(): number | null {
  const match = /^#\/tasks\/(\d+)$/.exec(window.location.hash);
  return match ? Number(match[1]) : null;
}

export function App() {
  const [loggedIn, setLoggedIn] = useState(getToken() !== null);
  const [taskId, setTaskId] = useState(currentTaskId());

  useEffect(() => {
    const onHashChange = () => setTaskId(currentTaskId());
    window.addEventListener("hashchange", onHashChange);
    return () => window.removeEventListener("hashchange", onHashChange);
  }, []);

  if (!loggedIn) return <Login onLogin={() => setLoggedIn(true)} />;

  return (
    <main>
      <header>
        <strong>Kairos</strong>{" "}
        <button
          type="button"
          onClick={() => {
            clearToken();
            setLoggedIn(false);
          }}
        >
          Log out
        </button>
      </header>
      {taskId === null ? <TaskList /> : <TaskPage id={taskId} />}
    </main>
  );
}

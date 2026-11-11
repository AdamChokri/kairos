import { useEffect, useState } from "react";

import { SESSION_ENDED, clearToken, getToken } from "./api";
import { Login } from "./Login";
import { Workspace } from "./Workspace";

function currentTaskId(): number | null {
  const match = /^#\/tasks\/(\d+)$/.exec(window.location.hash);
  return match ? Number(match[1]) : null;
}

export function App() {
  const [loggedIn, setLoggedIn] = useState(getToken() !== null);
  const [taskId, setTaskId] = useState(currentTaskId());
  const [notice, setNotice] = useState("");

  useEffect(() => {
    const onHashChange = () => setTaskId(currentTaskId());
    // The API refused the token (it expired or was revoked): back to the log-in form, with the reason.
    const onSessionEnded = () => {
      setNotice("Your session has ended. Log in again.");
      setLoggedIn(false);
    };
    window.addEventListener("hashchange", onHashChange);
    window.addEventListener(SESSION_ENDED, onSessionEnded);
    return () => {
      window.removeEventListener("hashchange", onHashChange);
      window.removeEventListener(SESSION_ENDED, onSessionEnded);
    };
  }, []);

  if (!loggedIn) {
    return (
      <Login
        notice={notice}
        onLogin={() => {
          setNotice("");
          setTaskId(currentTaskId());
          setLoggedIn(true);
        }}
      />
    );
  }

  return (
    <Workspace
      taskId={taskId}
      onLogout={() => {
        clearToken();
        // The next person to log in on this browser must not land on this person's task.
        window.history.replaceState(null, "", window.location.pathname);
        setTaskId(null);
        setNotice("");
        setLoggedIn(false);
      }}
    />
  );
}

import { type FormEvent, useId, useState } from "react";

import { login, register } from "./api";
import { AlertIcon, Mark } from "./Icons";

// The first screen: a dark panel that says what Kairos is, and the form. `notice` is why the person is here again
// (the session ended); the API's own refusal ("Invalid credentials") is shown as an error under the fields.
export function Login({ onLogin, notice = "" }: { onLogin: () => void; notice?: string }) {
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [creating, setCreating] = useState(false);
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  const userId = useId();
  const passwordId = useId();
  const hintId = useId();

  async function submit(event: FormEvent) {
    event.preventDefault();
    setError("");
    setBusy(true);
    try {
      if (creating) await register(username, password);
      await login(username, password);
      onLogin();
    } catch (problem) {
      setError(problem instanceof Error ? problem.message : "Something went wrong. Try again.");
      setBusy(false);
    }
  }

  return (
    <div className="login">
      <aside className="login-brand">
        <div className="wordmark">
          <Mark size={26} />
          <span>Kairos</span>
        </div>
        <p className="login-line">Your tasks and their comments in one place, and an assistant that turns a note into a task.</p>
      </aside>
      <main className="login-main">
        <form className="login-form" onSubmit={submit} aria-label={creating ? "Register" : "Log in"}>
          <h1>{creating ? "Create your account" : "Log in"}</h1>
          {notice && !error && (
            <p className="notice" role="status">
              {notice}
            </p>
          )}
          <div className="field">
            <label htmlFor={userId}>Username</label>
            <input
              id={userId}
              value={username}
              onChange={(e) => setUsername(e.target.value)}
              autoComplete="username"
              minLength={3}
              maxLength={64}
              required
            />
          </div>
          <div className="field">
            <label htmlFor={passwordId}>Password</label>
            <input
              id={passwordId}
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              autoComplete={creating ? "new-password" : "current-password"}
              minLength={8}
              maxLength={128}
              aria-describedby={creating ? hintId : undefined}
              required
            />
            {creating && <small id={hintId}>At least 8 characters.</small>}
          </div>
          {error && (
            <p className="alert" role="alert">
              <AlertIcon />
              <span>{error}</span>
            </p>
          )}
          <button className="btn btn-primary btn-wide" type="submit" disabled={busy}>
            {busy ? (creating ? "Creating the account…" : "Logging in…") : creating ? "Create account" : "Log in"}
          </button>
          <button
            className="btn-link"
            type="button"
            onClick={() => {
              setCreating(!creating);
              setError("");
            }}
          >
            {creating ? "I already have an account" : "New to Kairos? Create an account"}
          </button>
        </form>
      </main>
    </div>
  );
}

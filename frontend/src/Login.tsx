import { type FormEvent, useState } from "react";

import { login, register } from "./api";

export function Login({ onLogin }: { onLogin: () => void }) {
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [creating, setCreating] = useState(false);
  const [error, setError] = useState("");

  async function submit(event: FormEvent) {
    event.preventDefault();
    setError("");
    try {
      if (creating) await register(username, password);
      await login(username, password);
      onLogin();
    } catch (problem) {
      setError(problem instanceof Error ? problem.message : "Something went wrong");
    }
  }

  return (
    <form onSubmit={submit} aria-label={creating ? "Register" : "Log in"}>
      <h1>Kairos</h1>
      <label>
        Username
        <input value={username} onChange={(e) => setUsername(e.target.value)} required />
      </label>
      <label>
        Password
        <input
          type="password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          minLength={8}
          required
        />
      </label>
      {error && <p role="alert">{error}</p>}
      <button type="submit">{creating ? "Create account" : "Log in"}</button>
      <button type="button" onClick={() => setCreating(!creating)}>
        {creating ? "I have an account" : "New here? Register"}
      </button>
    </form>
  );
}

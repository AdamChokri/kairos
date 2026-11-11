// Calls to the API. As-is, the SPA talks to the API directly on port 8000 of the same host
// (the API allows any origin, SV-08); the to-be build goes through nginx under /api.
export const API_URL: string =
  import.meta.env.VITE_API_URL ?? `${window.location.protocol}//${window.location.hostname}:8000`;

const TOKEN_KEY = "kairos_token";

// Sent on the window when the API says the token is no longer good: the app returns to the log-in form.
export const SESSION_ENDED = "kairos:session-ended";

export interface Task {
  id: number;
  title: string;
  description: string;
  done: boolean;
  owner_id: number;
}

export interface Comment {
  id: number;
  task_id: number;
  author_id: number;
  body: string;
  created_at: string;
}

export const getToken = (): string | null => localStorage.getItem(TOKEN_KEY);
export const setToken = (token: string): void => localStorage.setItem(TOKEN_KEY, token);
export const clearToken = (): void => localStorage.removeItem(TOKEN_KEY);

export async function request<T>(path: string, init: RequestInit = {}): Promise<T> {
  const headers = new Headers(init.headers);
  headers.set("Content-Type", "application/json");
  const token = getToken();
  if (token) headers.set("Authorization", `Bearer ${token}`);

  const response = await fetch(`${API_URL}${path}`, { ...init, headers });
  if (!response.ok) {
    // A 401 on any call but the log-in itself means the token has expired or was revoked.
    if (response.status === 401 && !path.startsWith("/api/auth/")) {
      clearToken();
      window.dispatchEvent(new Event(SESSION_ENDED));
      throw new Error("Your session has ended. Log in again.");
    }
    // A server fault has nothing the person can act on in its own words: say what to do instead.
    if (response.status >= 500) throw new Error("The server had a problem. Try again in a moment.");
    const body: unknown = await response.json().catch(() => null);
    const detail = (body as { detail?: unknown } | null)?.detail;
    if (typeof detail === "string") throw new Error(detail);
    throw new Error(
      response.status === 422
        ? "Some of the values are not accepted. Check them and try again."
        : `Something went wrong (error ${response.status}).`,
    );
  }
  return response.status === 204 ? (undefined as T) : ((await response.json()) as T);
}

export async function login(username: string, password: string): Promise<void> {
  const result = await request<{ access_token: string }>("/api/auth/login", {
    method: "POST",
    body: JSON.stringify({ username, password }),
  });
  setToken(result.access_token);
}

export async function register(username: string, password: string): Promise<void> {
  await request("/api/auth/register", {
    method: "POST",
    body: JSON.stringify({ username, password }),
  });
}

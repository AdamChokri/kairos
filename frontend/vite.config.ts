import react from "@vitejs/plugin-react";
import { defineConfig } from "vitest/config";

// As-is (SV-09): the Vite dev server is what the container runs, on every interface, and it
// accepts any Host header. WP4.5 serves the static build from nginx instead.
export default defineConfig({
  plugins: [react()],
  server: { host: "0.0.0.0", port: 5173, allowedHosts: true },
  test: { environment: "jsdom" },
});

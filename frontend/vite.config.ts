import react from "@vitejs/plugin-react";
import { defineConfig } from "vitest/config";

// The development server listens on the loopback only (SV-09, fixed in WP4.5). The container serves the
// static build from nginx (frontend/nginx.conf), never this server.
export default defineConfig({
  plugins: [react()],
  server: { host: "127.0.0.1", port: 5173 },
  test: { environment: "jsdom" },
});

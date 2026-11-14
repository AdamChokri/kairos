# Kairos web (plan WP4.5, SV-09 fixed). Two stages:
#   build    the pinned Node image of ci/tools/node-image.txt compiles the SPA (npm ci, no install scripts);
#   runtime  nginx-unprivileged (pinned in ci/tools/tools.lock) serves the static files on 8080 as UID 101
#            and proxies /api to the API, so the browser sees one origin. No Node, no source, no dev server.
FROM node:26.13.0-slim@sha256:e4db4c914bf8ad241bd24804fc25d272d89bad97e68cdc8a1414862790a02c39 AS build

WORKDIR /src
COPY package.json package-lock.json ./
RUN npm ci --ignore-scripts
COPY . .
# The SPA calls the API on its own origin, under /api (nginx proxies it): an empty base URL.
ENV VITE_API_URL=""
RUN npm run build

FROM nginxinc/nginx-unprivileged:1.31.7-alpine3.24@sha256:b5047b9b76845eac124358373c6852377c52e4b05834a47647e955dd91cb8f1e

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /src/dist /usr/share/nginx/html
USER 101:101
EXPOSE 8080
HEALTHCHECK --interval=10s --timeout=4s --start-period=5s --retries=5 \
    CMD ["wget", "-q", "-O", "/dev/null", "http://127.0.0.1:8080/nginx-health"]

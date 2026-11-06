# Kairos web - the as-is image (plan WP2.1, SV-09): the Vite development server, in a node:latest
# container that runs as root, with every source file and every development tool inside.
# WP4.5 serves the static build from nginx-unprivileged instead.
FROM node:latest

WORKDIR /app
COPY package.json package-lock.json ./
RUN npm install

COPY . .
EXPOSE 5173
CMD ["npm", "run", "dev", "--", "--host", "0.0.0.0"]

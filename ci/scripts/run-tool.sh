#!/usr/bin/env bash
# ci/scripts/run-tool.sh [options] TOOL [ARGS...] - runs one pinned tool image the sandboxed way (plan WP4.2, D-12).
# TOOL is a name of ci/tools/tools.lock, or `node`. The image is always the digest of the lock. The container:
#   - is removed afterwards, has a read-only root filesystem and one tmpfs at /tmp (Docker mounts it noexec: nothing can run
#     from it, unless --exec-tmp is given), no capability, no new privilege;
#   - runs as the caller's own user and group, with a 2 GB memory limit and a process limit;
#   - sees the workspace at /src READ-ONLY and a writable reports directory at /reports;
#   - has no network unless --network is given, and never gets the Docker socket.
# Options (before the tool name):
#   --network            allow the network (the tool downloads its rules, packages or database)
#   --exec-tmp           mount the /tmp tmpfs with exec (nosuid and nodev stay): for a tool that downloads programs into its cache
#                        under /tmp and runs them from there. Only the Sonar scanner, which provisions its JRE that way (D-43)
#   --hosts              add the lab names of this machine's /etc/hosts (*.kairos.lab) to the container, which does not read it
#   --rw                 mount the workspace read-write at /src (only build_test.sh does this: it installs and builds)
#   --env NAME           pass the environment variable NAME by name, never by value (a secret stays out of the command line)
#   --volume NAME:PATH   a named Docker volume, for a cache (the Trivy database, the KEV catalog)
#   --entrypoint CMD     replace the image's entrypoint (see below for the default)
#   --workdir DIR        the working directory inside the container (default /src)
# The entrypoint: `run-tool.sh TOOL COMMAND ARGS` runs COMMAND, whatever the image defines. Several of the pinned images set
# an ENTRYPOINT of their own (trivy, gitleaks, syft), and Docker passes the arguments to it, so `trivy trivy image ...`
# would have run `trivy trivy image ...`. The entrypoint is therefore cleared for every tool (`--entrypoint=`), and a
# script names the binary it wants (`trivy`, `gitleaks`, `/syft`). The one exception is sonar-scanner: the entrypoint script
# of that image turns SONAR_TOKEN into -Dsonar.token and starts the scanner, which is how the first analysis ran.
# Needs Docker. Exit code: the container's own.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=/dev/null
source "$ROOT/ci/scripts/lib.sh"
# shellcheck disable=SC2034  # read by lib.sh (die)
CONTROL=run-tool

network=none
tmp_mount=/tmp
add_hosts=0
src_mode=ro
workdir=/src
entrypoint=(--entrypoint=)
extra=()
while (( $# > 0 )); do
  case "$1" in
    --network) network=bridge; shift ;;
    --exec-tmp) tmp_mount=/tmp:rw,exec,nosuid,nodev; shift ;;
    --hosts) add_hosts=1; shift ;;
    --rw) src_mode=rw; shift ;;
    --env) [[ ${2:-} =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || die "--env wants a variable name"; extra+=(-e "$2"); shift 2 ;;
    --volume) [[ ${2:-} == *:/* ]] || die "--volume wants NAME:/path"; extra+=(-v "$2"); shift 2 ;;
    --entrypoint) entrypoint=(--entrypoint "${2:?--entrypoint wants a command}"); shift 2 ;;
    --workdir) workdir="${2:?--workdir wants a directory}"; shift 2 ;;
    --*) die "unknown option $1" ;;
    *) break ;;
  esac
done
(( $# > 0 )) || die "usage: run-tool.sh [options] TOOL [ARGS...]"
tool="$1"; shift
image="$(tool_ref "$tool")"
# The image's own entrypoint script is kept for the Sonar scanner only (see the header), unless --entrypoint was given.
if [[ $tool == sonar-scanner && ${entrypoint[0]} == --entrypoint= ]]; then entrypoint=(); fi

hosts=()
if (( add_hosts )); then
  # Containers do not read the agent's /etc/hosts, where Ansible keeps the lab names.
  while read -r address names; do
    for name in $names; do
      [[ $name == *.kairos.lab ]] && hosts+=(--add-host "$name:$address")
    done
  done < <(grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+[[:space:]]' /etc/hosts || true)
fi

mkdir -p "$ROOT/reports"
exec docker run --rm --read-only --tmpfs "$tmp_mount" --cap-drop ALL --security-opt no-new-privileges \
  --user "$(id -u):$(id -g)" --memory 2g --pids-limit 512 -e HOME=/tmp \
  --network "$network" "${hosts[@]}" "${extra[@]}" "${entrypoint[@]}" \
  -v "$ROOT:/src:$src_mode" -v "$ROOT/reports:/reports" -w "$workdir" \
  "$image" "$@"

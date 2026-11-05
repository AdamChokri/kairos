#!/usr/bin/env bash
# infra/lab/reachability.sh - checks, from WSL2, every internet endpoint the plan depends on
# (plan WP0.2, section 14) and prints a Markdown table for docs/lab/capacity.md.
# "reachable" = DNS, TCP and TLS all worked and the server answered with any HTTP status: a 401,
# 403 or 404 from an API root is still a working route. Run it at home, then once at school.
# Exit code 0 only when every endpoint is reachable.
set -uo pipefail

ENDPOINTS=(
  "http://archive.ubuntu.com/ubuntu/|Ubuntu packages (apt, port 80)"
  "http://security.ubuntu.com/ubuntu/|Ubuntu security updates (apt, port 80)"
  "https://download.docker.com/|Docker Engine packages"
  "https://registry-1.docker.io/v2/|Docker Hub registry"
  "https://auth.docker.io/token|Docker Hub token service"
  "https://production.cloudflare.docker.com/|Docker Hub image layers"
  "https://ghcr.io/v2/|GitHub container registry"
  "https://quay.io/v2/|Quay registry"
  "https://mirror.gcr.io/v2/|Google registry mirror"
  "https://pypi.org/simple/|PyPI index"
  "https://files.pythonhosted.org/|PyPI files"
  "https://registry.npmjs.org/|npm registry"
  "https://github.com/|GitHub"
  "https://api.github.com/|GitHub API"
  "https://updates.jenkins.io/|Jenkins update center"
  "https://get.jenkins.io/|Jenkins downloads"
  "https://packages.wazuh.com/|Wazuh packages"
  "https://semgrep.dev/|Semgrep rules registry"
  "https://rekor.sigstore.dev/|Sigstore transparency log"
  "https://tuf-repo-cdn.sigstore.dev/|Sigstore trust root (TUF)"
  "https://fulcio.sigstore.dev/|Sigstore certificate authority"
  "https://slack.com/|Slack"
  "https://hooks.slack.com/|Slack incoming webhooks"
  "https://www.cisa.gov/sites/default/files/feeds/known_exploited_vulnerabilities.json|CISA KEV feed"
  "https://api.deepseek.com/|DeepSeek API"
  "https://keyserver.ubuntu.com/|Ubuntu key server (ISO signature)"
  "https://releases.ubuntu.com/24.04/|Ubuntu ISO downloads"
)
# GitHub serves release files from another host; follow one real download to prove that route too.
RELEASE_FILE="https://github.com/openbao/openbao/releases/download/v2.7.2/checksums.txt"

failures=0
echo "Reachability from $(hostname) on $(date -u +%Y-%m-%dT%H:%MZ)"
echo
echo "| Endpoint | Purpose | Result |"
echo "|---|---|---|"
for entry in "${ENDPOINTS[@]}"; do
  url=${entry%%|*} purpose=${entry#*|}
  code=$(curl -sS -o /dev/null -m 15 --connect-timeout 8 -w '%{http_code}' -r 0-1023 "$url" 2>/tmp/kairos-reach.err)
  rc=$?
  if [[ $rc -eq 0 && $code != 000 ]]; then
    result="reachable (HTTP $code)"
  else
    result="**FAILED** ($(head -c 120 /tmp/kairos-reach.err | tr -d '\n' | sed 's/^curl: //'))"
    failures=$((failures + 1))
  fi
  host=${url#*://}; host=${host%%/*}
  echo "| \`$host\` | $purpose | $result |"
done
final=$(curl -sS -L -o /dev/null -m 30 -w '%{http_code} %{url_effective}' "$RELEASE_FILE" 2>/tmp/kairos-reach.err)
if [[ $? -eq 0 && $final == 200\ * ]]; then
  served=${final#* }; served=${served#*://}; served=${served%%/*}
  echo "| \`$served\` | GitHub release files (followed a real download) | reachable (HTTP 200) |"
else
  echo "| GitHub release files | followed a real download | **FAILED** ($(head -c 120 /tmp/kairos-reach.err | tr -d '\n')) |"
  failures=$((failures + 1))
fi
rm -f /tmp/kairos-reach.err
echo
echo "$failures endpoint(s) failed."
(( failures == 0 ))

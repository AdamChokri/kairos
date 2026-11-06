#!/usr/bin/env bash
# ci/tools/install-scan-tools.sh [trivy] [hadolint] - installs the scanners that are single binaries into
# ~/.local/bin, verified (plan D-12): Trivy first used in WP2.1 (the checklist of the seeded weaknesses),
# Hadolint in WP3.2 (the Dockerfile hook). Without an argument it installs both. Gitleaks (P0) and cosign
# (P1) are already there.
#   Hadolint 2.15.1  the SHA-256 that the release publishes in its checksums.sha256, pinned below.
#   Trivy 0.76.1     the release's checksums file must carry a Sigstore signature made by the release
#                    workflow of aquasecurity/trivy for exactly this tag (checked keylessly with cosign,
#                    as for OpenBao), and the archive must match both that file and the hash pinned below.
# Run again after a pin changes; with the right version installed it does nothing.
#   bash ci/tools/install-scan-tools.sh trivy
#   bash ci/tools/install-scan-tools.sh
# HOOK_TOOLS_BIN=<dir> installs somewhere else (used by the tests). Needs curl, tar, sha256sum, cosign.
set -Eeuo pipefail

BIN="${HOOK_TOOLS_BIN:-$HOME/.local/bin}"

HADOLINT_VERSION="2.15.1"
HADOLINT_SHA256="c7187db94eeeeca956519a6af171adc31453941a1e777961f6e680f697c8c507"

TRIVY_VERSION="0.76.1"
TRIVY_ARCHIVE_SHA256="c7cbe3137fb8a48a17574bede3dd6beb16742d1e9772929940fc90082c39d9c0"
TRIVY_IDENTITY="https://github.com/aquasecurity/trivy/.github/workflows/reusable-release.yaml@refs/tags/v${TRIVY_VERSION}"
TRIVY_ISSUER="https://token.actions.githubusercontent.com"

want=("$@")
(( ${#want[@]} > 0 )) || want=(trivy hadolint)
for item in "${want[@]}"; do
  [[ $item == trivy || $item == hadolint ]] || { echo "usage: install-scan-tools.sh [trivy] [hadolint]" >&2; exit 2; }
done
wanted() { local item; for item in "${want[@]}"; do [[ $item == "$1" ]] && return 0; done; return 1; }

for tool in curl tar sha256sum; do
  command -v "$tool" >/dev/null || { echo "install-scan-tools: missing tool: $tool" >&2; exit 1; }
done
mkdir -p "$BIN"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

fetch() { curl -fsSL --retry 3 -o "$2" "$1"; }

# --- Hadolint ---
if ! wanted hadolint; then
  :
elif [[ "$("$BIN/hadolint" --version 2>/dev/null | awk '{print $NF}')" == "$HADOLINT_VERSION" ]]; then
  echo "hadolint $HADOLINT_VERSION: already installed"
else
  base="https://github.com/hadolint/hadolint/releases/download/v${HADOLINT_VERSION}"
  fetch "$base/hadolint-linux-x86_64" "$work/hadolint"
  fetch "$base/checksums.sha256" "$work/hadolint.sums"
  echo "hadolint: the release's own checksums.sha256 must name the pinned hash"
  grep -E "^${HADOLINT_SHA256} \\*hadolint-linux-x86_64\$" "$work/hadolint.sums" >/dev/null ||
    { echo "install-scan-tools: the published checksum of hadolint ${HADOLINT_VERSION} is not the pinned one - stop and tell the project owner" >&2; exit 1; }
  echo "${HADOLINT_SHA256}  $work/hadolint" | sha256sum --check --strict -
  install -m 0755 "$work/hadolint" "$BIN/hadolint"
  echo "installed hadolint $("$BIN/hadolint" --version | awk '{print $NF}') to $BIN/hadolint"
fi

# --- Trivy ---
if ! wanted trivy; then
  :
elif [[ "$("$BIN/trivy" --version 2>/dev/null | awk 'NR==1 {print $2}')" == "$TRIVY_VERSION" ]]; then
  echo "trivy $TRIVY_VERSION: already installed"
else
  command -v cosign >/dev/null || { echo "install-scan-tools: cosign is missing (P1: ~/.local/bin/cosign)" >&2; exit 1; }
  base="https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}"
  archive="trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz"
  sums="trivy_${TRIVY_VERSION}_checksums.txt"
  fetch "$base/$archive" "$work/$archive"
  fetch "$base/$sums" "$work/$sums"
  fetch "$base/$sums.sigstore.json" "$work/$sums.sigstore.json"
  echo "trivy: verifying the signature of $sums (signer: $TRIVY_IDENTITY)"
  cosign verify-blob --bundle "$work/$sums.sigstore.json" \
    --certificate-identity "$TRIVY_IDENTITY" --certificate-oidc-issuer "$TRIVY_ISSUER" "$work/$sums"
  echo "trivy: the archive must match the signed checksums and the pinned hash"
  (cd "$work" && grep -E "  ${archive}\$" "$sums" | sha256sum --check --strict -)
  echo "${TRIVY_ARCHIVE_SHA256}  $work/$archive" | sha256sum --check --strict -
  tar -xzf "$work/$archive" -C "$work" trivy
  install -m 0755 "$work/trivy" "$BIN/trivy"
  echo "installed trivy $("$BIN/trivy" --version | awk 'NR==1 {print $2}') to $BIN/trivy"
fi

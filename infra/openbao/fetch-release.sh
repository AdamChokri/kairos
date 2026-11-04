#!/usr/bin/env bash
# infra/openbao/fetch-release.sh VERSION - downloads an OpenBao release for linux/amd64 into the
# Legion's project folder, openbao\VERSION (infra/lab/provision.conf), and verifies it before
# anything uses it (plan WP1.3, D-12):
#   1. checksums.txt is verified keylessly with cosign: its Sigstore bundle must have been signed
#      by OpenBao's release workflow on the release/<major.minor>.x branch, through GitHub Actions;
#   2. the .deb (for dso-bao) and the .tar.gz (for the bao CLI) must match checksums.txt.
# Then installs the bao CLI to ~/.local/bin/bao from the verified archive.
# Re-running it re-verifies the files already downloaded; nothing is trusted unverified.
set -euo pipefail

VERSION=${1:-}
[[ $VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "usage: $0 VERSION   (for example 2.7.2)" >&2; exit 2; }
LINE=${VERSION%.*}
BASE="https://github.com/openbao/openbao/releases/download/v$VERSION"
# shellcheck source-path=SCRIPTDIR source=../lab/provision.conf
source "$(dirname "${BASH_SOURCE[0]}")/../lab/provision.conf"
[[ -n $LAB_HOME_WSL ]] || { echo "ERROR: cannot map $LAB_ROOT_LEGION to a WSL2 path - run this in WSL2" >&2; exit 1; }
DEST="$LAB_HOME_WSL/openbao/$VERSION"
IDENTITY="https://github.com/openbao/openbao/.github/workflows/release.yml@refs/heads/release/$LINE.x"
ISSUER="https://token.actions.githubusercontent.com"
FILES=(checksums.txt checksums.txt.sigstore.json "openbao_${VERSION}_linux_amd64.deb" "openbao_${VERSION}_linux_amd64.tar.gz")

for tool in curl cosign sha256sum tar install; do
  command -v "$tool" >/dev/null 2>&1 || { echo "ERROR: missing tool: $tool" >&2; exit 1; }
done

mkdir -p "$DEST"
cd "$DEST"
for f in "${FILES[@]}"; do
  if [[ ! -s $f ]]; then
    echo "downloading $f"
    curl -sSfL --retry 3 -o "$f.part" "$BASE/$f"
    mv "$f.part" "$f"
  fi
done

echo "verifying the signature of checksums.txt (signer: $IDENTITY)"
cosign verify-blob --bundle checksums.txt.sigstore.json \
  --certificate-identity "$IDENTITY" --certificate-oidc-issuer "$ISSUER" checksums.txt

echo "verifying the downloaded files against checksums.txt"
for f in "openbao_${VERSION}_linux_amd64.deb" "openbao_${VERSION}_linux_amd64.tar.gz"; do
  grep -E "  $f\$" checksums.txt | sha256sum --check --strict -
done

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT
tar -xzf "openbao_${VERSION}_linux_amd64.tar.gz" -C "$workdir" bao
install -D -m 0755 "$workdir/bao" "$HOME/.local/bin/bao"
echo "installed $("$HOME/.local/bin/bao" version) to ~/.local/bin/bao"
echo "verified package for dso-bao: $DEST/openbao_${VERSION}_linux_amd64.deb"

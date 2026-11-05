#!/usr/bin/env bash
# ci/tools/pin-images.sh - refreshes the digest of every pinned image in the lab's two pin files
# (plan D-08, D-12): the image_* lines of infra/ansible/group_vars/all/images.yml and the FROM lines
# of ci/jenkins/Dockerfile. The tag written in each line is kept; only its digest is resolved again
# (ci/tools/resolve-digest.sh). Prints what changed; review with `git diff` before committing.
#   ci/tools/pin-images.sh            every image
#   ci/tools/pin-images.sh KEY...     only these image_* keys (for example image_sonarqube)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RESOLVE="$ROOT/ci/tools/resolve-digest.sh"
IMAGES="$ROOT/infra/ansible/group_vars/all/images.yml"
DOCKERFILE="$ROOT/ci/jenkins/Dockerfile"
want=("$@")

selected() {
  (( ${#want[@]} == 0 )) && return 0
  local w; for w in "${want[@]}"; do [[ $w == "$1" ]] && return 0; done
  return 1
}

changed=0
repin() {  # FILE LINE_PREFIX_REGEX KEY REF  -> rewrites that line with a fresh digest
  local file=$1 prefix=$2 key=$3 old=$4 tagref new
  tagref=${old%@*}
  new=$("$RESOLVE" "$tagref")
  if [[ $new == "$old" ]]; then
    printf '  unchanged %-30s %s\n' "$key" "$new"
  else
    python3 -I - "$file" "$prefix" "$old" "$new" <<'PY'
import re, sys
path, prefix, old, new = sys.argv[1:]
text = open(path).read()
pattern = re.compile("(" + prefix + r'"?)' + re.escape(old) + '("?)$', re.M)
text, n = pattern.subn(lambda m: m.group(1) + new + m.group(2), text)
if n != 1:
    sys.exit(f"ERROR: expected exactly one line for {old} in {path}, found {n}")
open(path, "w").write(text)
PY
    printf '  pinned    %-30s %s\n' "$key" "$new"
    changed=$((changed + 1))
  fi
}

echo "$IMAGES"
mapfile -t lines < "$IMAGES"   # read first: repin rewrites the file
for line in "${lines[@]}"; do
  [[ $line =~ ^(image_[a-z0-9_]+):[[:space:]]+\"?([^\"[:space:]]+)\"?$ ]] || continue
  key=${BASH_REMATCH[1]} ref=${BASH_REMATCH[2]}
  selected "$key" || continue
  repin "$IMAGES" "^$key:\\s+" "$key" "$ref"
done

if selected image_jenkins_base; then
  echo "$DOCKERFILE"
  mapfile -t lines < "$DOCKERFILE"
  for line in "${lines[@]}"; do
    [[ $line =~ ^FROM[[:space:]]+([^[:space:]]+) ]] || continue
    repin "$DOCKERFILE" '^FROM\s+' image_jenkins_base "${BASH_REMATCH[1]}"
  done
fi
echo "$changed line(s) changed."

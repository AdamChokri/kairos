#!/usr/bin/env bash
# ci/jenkins/pin-plugins.sh - pins every controller plugin, dependencies included (plan WP1.4, D-12).
# Reads the plugins that jenkins-plugin-cli actually installed into the image built on dso-jenkins
# (the tag Ansible recorded in /opt/jenkins/image-tag), takes each one's version from its own
# manifest, and rewrites ci/jenkins/plugins.txt: first the plugins the plan asks for, then their
# dependencies - all as name:version. Rebuild the image afterwards (the Ansible role does it when
# the file changes) and review `git diff ci/jenkins/plugins.txt`.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGINS="$DIR/plugins.txt"
: "${JENKINS_VM:=dso-jenkins}"
: "${LAB_ADMIN_USER:=adam}"
: "${LAB_ADMIN_KEY:=$HOME/.ssh/kairos_admin}"

ssh_vm() { ssh -i "$LAB_ADMIN_KEY" -o IdentitiesOnly=yes -o BatchMode=yes "$LAB_ADMIN_USER@$JENKINS_VM" "$@"; }

tag=$(ssh_vm cat /opt/jenkins/image-tag) || { echo "ERROR: no /opt/jenkins/image-tag on $JENKINS_VM - run the jenkins play first" >&2; exit 1; }
[[ $tag =~ ^[0-9a-f]{12,64}$ ]] || { echo "ERROR: unexpected image tag '$tag'" >&2; exit 1; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
ssh_vm "sudo docker run --rm --entrypoint tar kairos/jenkins-controller:$tag -C /usr/share/jenkins/ref/plugins -cf - ." > "$work/plugins.tar"

python3 -I - "$work/plugins.tar" "$PLUGINS" <<'PY'
import io, sys, tarfile, zipfile

tar_path, plugins_path = sys.argv[1], sys.argv[2]

def manifest(data):
    """Return the main section of a JAR manifest as a dict (continuation lines start with a space)."""
    lines, out = data.decode("utf-8").splitlines(), {}
    joined = []
    for line in lines:
        if line.startswith(" ") and joined:
            joined[-1] += line[1:]
        elif line:
            joined.append(line)
        else:
            break
    for line in joined:
        key, _, value = line.partition(": ")
        out[key] = value
    return out

found = {}
with tarfile.open(tar_path) as tar:
    for member in tar.getmembers():
        name = member.name.rsplit("/", 1)[-1]
        if not member.isfile() or not name.endswith((".jpi", ".hpi")):
            continue
        with zipfile.ZipFile(io.BytesIO(tar.extractfile(member).read())) as z:
            m = manifest(z.read("META-INF/MANIFEST.MF"))
        short, version = m.get("Short-Name"), m.get("Plugin-Version")
        if not short or not version:
            sys.exit(f"ERROR: {name} has no Short-Name/Plugin-Version in its manifest")
        found[short] = version

if not found:
    sys.exit("ERROR: no plugin found in the image")

requested = []
with open(plugins_path) as f:
    for line in f:
        line = line.split("#", 1)[0].strip()
        if line:
            requested.append(line.split(":", 1)[0])
missing = [p for p in requested if p not in found]
if missing:
    sys.exit("ERROR: requested but not installed: " + ", ".join(missing))

deps = sorted(p for p in found if p not in requested)
with open(plugins_path, "w") as f:
    f.write("# ci/jenkins/plugins.txt - controller plugins (plan WP1.4), every one pinned, written by\n")
    f.write("# ci/jenkins/pin-plugins.sh from the image it built. Change versions only through a pull request.\n")
    f.write("# Requested by the plan:\n")
    for p in requested:
        f.write(f"{p}:{found[p]}\n")
    f.write("# Their dependencies, pinned too:\n")
    for p in deps:
        f.write(f"{p}:{found[p]}\n")
print(f"pinned {len(requested)} requested plugins and {len(deps)} dependencies in {plugins_path}")
PY

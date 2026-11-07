#!/usr/bin/env bash
# ci/tools/check-rule-links.sh - WP3.3 done-when: every Semgrep rule of security/semgrep/ links to a
# section of docs/secure-coding.md that exists, in its message and in its metadata, and has a test
# fixture of the same name in security/semgrep/tests/. Prints one line per rule; exit code 1 on any gap.
#   bash ci/tools/check-rule-links.sh        Needs python3 and nothing else.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
python3 -I - "$ROOT" <<'PY'
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
guide = (root / "docs/secure-coding.md").read_text(encoding="utf-8")


def slug(heading: str) -> str:
    """The anchor GitHub gives a heading: lower case, punctuation dropped, spaces to hyphens."""
    text = re.sub(r"[^\w\- ]", "", heading.strip().lower())
    return text.replace(" ", "-")


anchors = {slug(m.group(1)) for m in re.finditer(r"^#{1,6}\s+(.+?)\s*$", guide, re.M)}
problems = 0
rules = sorted((root / "security/semgrep").glob("*.yaml"))
if not rules:
    sys.exit("check-rule-links: no rule found in security/semgrep/")

for path in rules:
    text = path.read_text(encoding="utf-8")
    rule_id = re.search(r"^\s*-\s+id:\s+(\S+)", text, re.M)
    message = re.search(r"^\s+message:\s*>-?\n((?:\s{6,}.*\n)+)", text, re.M)
    guide_meta = re.search(r"^\s+guide:\s+docs/secure-coding\.md#([a-z0-9-]+)\s*$", text, re.M)
    link = re.search(r"docs/secure-coding\.md#([a-z0-9-]+)", message.group(1)) if message else None
    errors = []
    if not rule_id:
        errors.append("no rule id")
    if not link:
        errors.append("the message has no link to docs/secure-coding.md#...")
    if not guide_meta:
        errors.append("metadata.guide is missing")
    if link and guide_meta and link.group(1) != guide_meta.group(1):
        errors.append("the message and metadata.guide name different sections")
    for found in (link, guide_meta):
        if found and found.group(1) not in anchors:
            errors.append(f"docs/secure-coding.md has no section #{found.group(1)}")
    if not any((root / "security/semgrep/tests").glob(path.stem + ".*")):
        errors.append("no fixture named like the rule in security/semgrep/tests/")
    for key in ("owasp:", "cwe:", "asvs:"):
        if key not in text:
            errors.append(f"metadata lacks {key[:-1]}")
    if errors:
        problems += 1
        print(f"FAIL  {path.name}: " + "; ".join(errors))
    else:
        print(f"OK    {rule_id.group(1):45} -> #{link.group(1)}")

if problems:
    sys.exit(f"check-rule-links: {problems} rule(s) with problems")
print(f"check-rule-links: {len(rules)} rules, every one links to its guide section and has a fixture")
PY

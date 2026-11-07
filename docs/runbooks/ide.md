# IDE security profile

The developer's editor is the first control of the project: it shows a flaw while the line is still being typed (plan WP3.1). This page is the profile of the project's editor, **VS Code in WSL mode**, and the rules that keep its extensions trustworthy. The profile is code: `.vscode/extensions.json` (the list) and `.vscode/settings.json` (the settings) are in the repository, and a change to either goes through a pull request.

## What the profile contains

| Extension | Id | What it does here | Weakness it shows |
|---|---|---|---|
| Python | `ms-python.python` | Python language support, interpreter selection | — |
| Pylance | `ms-python.vscode-pylance` | Types and navigation; `python.analysis.extraPaths` points it at `backend/` | — |
| Ruff | `charliermarsh.ruff` | Lint and format as you type; `ruff.lint.extendSelect: ["S"]` turns on the `S` rules, which re-implement Bandit's checks in real time | SV-01 (S105), SV-02 (S608), SV-04 (S506), SV-05 (S324) |
| ESLint | `dbaeumer.vscode-eslint` | Runs the frontend's flat config, with its security rules; `eslint.workingDirectories` points it at `frontend/` | SV-03 (`react/no-danger`) |
| SonarQube for IDE | `SonarSource.sonarlint-vscode` | Real-time analysis; in Connected Mode it uses the lab server's rules and the quality profile of project `kairos` | SV-05 (`python:S4790`) |
| YAML | `redhat.vscode-yaml` | Syntax and schema checks for the Compose, Ansible and Jenkins files | — |

The interpreter is `backend/.venv/bin/python` (`python.defaultInterpreterPath`): the environment that `uv sync` creates in `backend/`. Without it, Pylance cannot resolve the project's packages and marks every import.

**The Hadolint extension is not in the list** (plan WP3.1 names it). No publisher of a Hadolint extension could be verified as the Hadolint project, and the Dockerfile check does not depend on it: the pre-commit hook `hadolint` (WP3.2) runs the pinned, checksum-verified binary on every Dockerfile that changes (E-37).

## Extension hygiene (D-12)

Two security extensions were compromised in early 2026 (the Trivy extension for VS Code, and Checkmarx's extensions on Open VSX), so an extension is code that runs with your permissions and is treated like a dependency:

1. **Only the six ids above.** Install them by the exact id in `.vscode/extensions.json` (`code --install-extension <id>`, or the recommendations in the Extensions view), never from a search result. On the extension's page, the *Identifier* must be the id of the list, and the publisher's name must be the maker's, with the verified mark where the marketplace shows one: the page shows the maker's name, which is not always the first part of the id (Astral Software for `charliermarsh.ruff`, Microsoft for `dbaeumer.vscode-eslint` and `ms-python.*`, SonarSource, Red Hat). A name or a domain that is not the maker's is a stop. The Python extension installs its own companions (published by `ms-python`, for example the debugger): those are accepted, and **any other id that appears is removed and reported**. `comm -13 <(python3 -c 'import json; print("\n".join(json.load(open(".vscode/extensions.json"))["recommendations"]))' | tr A-Z a-z | sort) <(code --list-extensions | tr A-Z a-z | sort)` prints the ids that are installed and not listed.
   A version is installed only when it is at least 7 days old (D-12). The editor has no *Version History* tab and the marketplace page lists only the newest builds, so the dates come from the marketplace's public query, which also tells a release from a pre-release (read-only, no login, no secret). This lists every installed extension with the date of its installed version; each line must say `release`, with a date at least 7 days before today:

   ```bash
   code --list-extensions --show-versions | grep @ | while IFS=@ read id ver; do echo -n "$id@$ver  "; curl -s -X POST https://marketplace.visualstudio.com/_apis/public/gallery/extensionquery -H 'Accept: application/json;api-version=7.1-preview.1' -H 'Content-Type: application/json' -d "{\"filters\":[{\"criteria\":[{\"filterType\":7,\"value\":\"$id\"}]}],\"flags\":17}" | python3 -c 'import sys,json;v=json.load(sys.stdin)["results"][0]["extensions"][0]["versions"];w=sys.argv[1];m=[x for x in v if x["version"]==w and x.get("targetPlatform") in (None,"universal","linux-x64")];print(*[(x["lastUpdated"][:10],"PRE-RELEASE" if any(p["key"]=="Microsoft.VisualStudio.Code.PreRelease" and p["value"]=="true" for p in x.get("properties",[])) else "release") for x in m[:1]] or ["not found"])' "$ver"; done
   ```

   A line that fails is fixed with *Install Specific Version…* (the gear menu), taking the newest `release` that is old enough; a pre-release is never chosen. The `ms-python` companions are held to the same rule.
2. **No automatic updates.** Run *Disable Auto Update for Extensions* from the Command Palette once. An extension is updated on purpose: read its release notes, wait the project's 7 days (D-12) after the release, then update it from the Extensions view and note the new version in the pull request that touches the list. The setting is stored as `"extensions.autoUpdate": "off"`: in this VS Code the box accepts only `"on"` or `"off"`.
3. **The list lives in the repository.** Adding an extension means adding its id to `.vscode/extensions.json` in a pull request that says why, who publishes it and what it can reach.
4. **No Trivy extension, no Open VSX.** Trivy runs as the pinned binary (the `trivy` hook and CI), never as an editor extension. The marketplace used is VS Code's own.
5. **Windows-side extensions.** A WSL window also uses the extensions installed on the Windows side (*Local - Installed* in the Extensions view) when they are UI extensions, and those run with your Windows permissions, outside WSL and outside the six ids (D-31). Open each one's page and its *Features* tab: a *Runtime Status*, activation events or commands mean it runs code; a pack that contributes only snippets or themes does not. An extension that runs code and is neither one of the six ids nor Microsoft's *WSL* extension is uninstalled from Windows (`code --uninstall-extension <id>` in PowerShell). Extensions marked **Built-in** are VS Code itself and are outside this rule. Repeat the check when the profile changes (IDE-02).

## Open the project (once per session)

From WSL2, at the repository root:

```bash
code .
```

The window's bottom-left corner must read **WSL: Ubuntu-24.04** (or the name of your distribution): the extensions then run inside WSL, next to the repository and the tools, and not on Windows. If it shows nothing, install *WSL* (Microsoft's `ms-vscode-remote.remote-wsl`) on the Windows side, once, and run `code .` again.

## SonarQube for IDE: Connected Mode

Connected Mode makes the editor use the same rules as the server, so the editor and the pipeline agree. The server is `http://sonar.kairos.lab:9000`.

- **The token is a new one.** The CI analysis token (`kv/ci/sonarqube`) is a *project analysis* token and does not work here: connected mode takes only a **user token**. Generate one at `http://sonar.kairos.lab:9000/account/security/`, name it `kairos-ide`, give it the expiry the page offers closest to 90 days, and paste it into VS Code's prompt. It is stored in VS Code's secret storage; it is never written into a file of the repository.
- **The connection:** Activity Bar → **SONARQUBE SETUP** → **CONNECTED MODE** → **Add SonarQube Server Connection**: *Server URL* `http://sonar.kairos.lab:9000`, *User Token* the token, *Connection Name* `kairos-lab` → **Save Connection**.
- **The binding:** in the same view, **Add Project Binding** → choose the folder → choose project `kairos` → **Save Connection**. A "Success!" notice confirms it. The binding is written into the repository's `.vscode/settings.json` as `sonarlint.connectedMode.project` (the connection's name, `kairos-lab`, and the project key, `kairos`: no address and no token), and VS Code reformats that file's ESLint entry while it is there. The file is committed with the profile. The connection itself (name and address) is stored in your user settings, outside the repository, and the token in the secret storage. `grep -A3 'connectedMode.project' .vscode/settings.json` shows the block, and `grep -c -i token .vscode/settings.json` must print `0`.
- **Sharing the binding** (optional, one time): reveal the connection and binding in the view and use the arrow icon (**Share Connected Mode Configuration**). It adds a `.json` file in `.sonarlint/` that holds the server URL and the project key and no token. Before committing it, open it and check that: a value that looks like a token means stop. Everyone still uses their own connection and token.

How to check that it works: the SonarQube view lists the binding to `kairos` under `kairos-lab` (Connected Mode), and opening `backend/app/security.py` shows `python:S4790` next to Ruff's `S324`. In P3 that was the only finding SonarQube for IDE reported in the seeded code: `tasks.py` and `importer.py` show Ruff's findings only (IDE-03, D-31).

## What to see when you open the seeded code (EV-05)

| File | Line | Expected | From |
|---|---|---|---|
| `backend/app/config.py` | `JWT_SECRET_KEY = "…"` | squiggle `S105` (SV-01) | Ruff |
| `backend/app/routers/tasks.py` | the search query built with an f-string | squiggle `S608` | Ruff |
| `backend/app/routers/importer.py` | `yaml.load(…, Loader=yaml.Loader)` | squiggle `S506` | Ruff |
| `backend/app/security.py` | the MD5 hash of the password | squiggle `S324` | Ruff; SonarQube for IDE adds `python:S4790` |
| `frontend/src/CommentList.tsx` | `dangerouslySetInnerHTML` | `react/no-danger` | ESLint |

A finding you do not recognise is a finding to report, not to switch off. A rule that is wrong for a line is silenced with a comment that names the rule and the reason (`# noqa: S105 - <why>`), never by turning the rule off for the project.

## When the profile changes

A new extension, a new setting or a new rule set is a pull request: the diff of `.vscode/` shows what changes, the description says why, and the checklist of `.github/pull_request_template.md` is filled in.

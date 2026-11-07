# Secure coding guide

This guide is what a blocked commit or push points to. Every custom Semgrep rule of Kairos (`security/semgrep/`) ends its message with a link to one section below, so the explanation arrives at the moment it is needed: the flaw, why it matters, how to fix it, and the standards it maps to. The sections are written for the code in this repository, and each one names the file where the weakness was seeded (`security/seeded-vulns.md`) and the test that proves the fix.

**Standards used.** OWASP Top 10:2025 for the category, CWE for the weakness, and OWASP ASVS 5.0.0 for the requirement. The project's target is ASVS level 1; a requirement of a higher level is marked, because it is a good practice here even when it is not required.

| ASVS 5.0 chapter | Focus for Kairos | Verified by |
|---|---|---|
| V1 Encoding and Sanitization | Bound parameters, output encoding, no unsafe deserialization | Semgrep, Bandit, SonarQube, tests |
| V3 Web Frontend Security | CSP, no raw HTML rendering, security headers | ESLint, ZAP, smoke tests |
| V6 Authentication | Argon2id, generic error messages | Bandit, tests |
| V8 Authorization | Object-level checks (IDOR) | Regression test, pentest |
| V9 Self-contained Tokens | Algorithm allow-list, signature and `exp` checks, key from a secret file | Tests, pentest |
| V12 Secure Communication | TLS 1.2+ only, HSTS | Smoke tests |
| V13 Configuration | Debug off, no secrets in code or config, docs disabled in production | Gitleaks, smoke tests |
| V15 Secure Coding and Architecture | Managed, pinned, inventoried dependencies | Trivy, Syft |

## How a blocked commit or push explains itself

| Stage | Tool | What happens |
|---|---|---|
| `git commit` | Gitleaks (`ci/tools/commit-scan.sh`), Bandit, Ruff, ESLint, Hadolint, `pre-commit-hooks` | The commit stops and the tool prints its finding. A secret is reported redacted, and the message names the section [Hard-coded secrets](#hard-coded-secrets). |
| `git push` | Semgrep, Trivy | The push stops. A Semgrep finding carries the message of its rule, which ends with the link to the section below; a Trivy finding names the package or the check. |
| Pull request | The Jenkins pipeline (P4) | The same rules run again, because a hook can be skipped and the pipeline cannot. |

A finding is never ignored by editing a rule or a scanner's configuration. If a finding is a false positive or must wait, the exemption process of the plan (section 4.3, WP4.4) records who accepted it, why, and until when.

---

## Hard-coded secrets

**Rule:** `kairos.hardcoded-jwt-secret` · Gitleaks · seeded as SV-01 in `backend/app/config.py`

### The flaw

A key, password or token is written in the source code or in a file that is committed:

```python
JWT_SECRET_KEY = "<a long random-looking string>"  # in the source: visible to everyone who can read the repository
```

Kairos v0 does this on purpose, with a fake value. Its `deploy/.env` is committed too, with the database password.

### Why it matters

Whoever can read the code can sign a valid token for any user (an authentication bypass) or open the database. This repository is public, and a pushed commit stays public even if it is reverted: the value is in the history, in every clone and in every fork. Rotating the secret means changing the code, so it is rarely done. The same value is usually shared by development, staging and production, so one leak opens all three.

### How to fix

1. Read the secret at run time from a file or the environment, and keep the value out of the repository:

   ```python
   from pathlib import Path
   import os

   JWT_SECRET_KEY = (
       Path(os.environ["JWT_SECRET_KEY_FILE"]).read_text(encoding="utf-8").strip()
   )
   ```

2. Give each environment its own value, held in OpenBao and rendered to a file on the host (WP5.3).
3. If a real secret was committed, treat it as public: rotate it first, and only then clean up. Rewriting history does not take back a copy somebody already holds.

### Checks

Gitleaks at commit time and in CI; the Semgrep rule above at push time and in CI; SonarQube on `main`. The regression test for the fix is in `backend/tests/` (WP4.5).

### References

- OWASP Top 10:2025: A04 Cryptographic Failures, A07 Authentication Failures
- CWE-798 Use of Hard-coded Credentials · CWE-321 Use of Hard-coded Cryptographic Key
- ASVS 5.0.0: 13.3.1 (secrets management, level 2: "secrets must not be included in application source code"), 9.1.3 (key material comes from a trusted pre-configured source, level 1)

### The two secrets Kairos v0 keeps on purpose

`security/seeded-secrets.tsv` lists the two fake values that SV-01 puts in the repository. `ci/tools/commit-scan.sh` accepts exactly those two findings and blocks every other one, and it blocks a change to a listed file that no longer matches the list. The list shrinks to nothing when SV-01 is fixed (WP4.5).

---

## SQL injection

**Rule:** `kairos.sql-fstring-in-text` · seeded as SV-02 in `backend/app/routers/tasks.py`

### The flaw

A value from the request becomes part of the SQL text:

```python
query = text(
    f"SELECT id, title FROM tasks WHERE title LIKE '%{search}%'"
)  # the search text is now SQL
```

### Why it matters

The database cannot tell the developer's SQL from the user's. A search for `' OR '1'='1` returns every row; a longer payload reads other tables, changes rows, or on some databases runs commands. In Kairos it returns another user's tasks, which is also a failure of authorization (SV-06).

### How to fix

Keep the SQL constant and pass values as bound parameters; the driver sends them separately from the statement:

```python
query = text(
    "SELECT id, title FROM tasks WHERE owner_id = :owner AND lower(title) LIKE lower(:pattern)"
)
rows = db.execute(query, {"owner": user.id, "pattern": f"%{search}%"})
```

The f-string that builds the *pattern* is fine: it builds a value, not the SQL. Better still, use the SQLAlchemy expression language, `select(Task).where(Task.owner_id == user.id, Task.title.ilike(f"%{search}%"))`, which binds every value for you. Table or column names cannot be bound: choose them from a fixed allow-list in code.

### Checks

Semgrep at push time and in CI, Bandit B608 (reported, below the blocking threshold), SonarQube, and the ZAP API scan against the running application. The regression test sends an injection payload and expects only the caller's tasks (WP4.5).

### References

- OWASP Top 10:2025: A05 Injection
- CWE-89 Improper Neutralization of Special Elements used in an SQL Command
- ASVS 5.0.0: 1.2.4 (queries use parameterized queries, ORMs or equivalent protection, level 1)

---

## Cross-site scripting

**Rule:** `kairos.react-dangerously-set-inner-html` · ESLint `react/no-danger` · seeded as SV-03 in `frontend/src/CommentList.tsx`

### The flaw

A value that comes from users is inserted into the page as HTML:

```tsx
<li dangerouslySetInnerHTML={{ __html: comment.body }} />   {/* the comment is now markup */}
```

### Why it matters

A comment such as `<img src=x onerror="...">` runs script in the browser of everyone who opens the task. The script runs as the logged-in user: it can read what the page can read, including the token that the single-page app keeps in `localStorage`, and call the API as that user. Because the comment is stored, one post attacks every reader (stored XSS).

### How to fix

Render the value as text. React escapes text children, so markup in the value is shown, not run:

```tsx
<li>{comment.body}</li>
```

If HTML really is required (a rich-text feature), sanitize it with a maintained library on a trusted layer first, and add a Content-Security-Policy that forbids inline script, so a missed case is still contained (WP5.3, SV-08).

### Checks

ESLint at commit time, Semgrep at push time and in CI, SonarQube, the ZAP scans. The regression test renders a comment holding an `<img onerror>` payload and expects inert text (Vitest, WP4.5).

### References

- OWASP Top 10:2025: A05 Injection
- CWE-79 Improper Neutralization of Input During Web Page Generation (Cross-site Scripting)
- ASVS 5.0.0: 1.2.1 (output encoding for the context, level 1), 3.2.2 (content meant as text is rendered with safe functions, level 1)

---

## Unsafe deserialization

**Rule:** `kairos.unsafe-yaml-load` · Bandit B506 · seeded as SV-04 in `backend/app/routers/importer.py`

### The flaw

Untrusted data is parsed with a loader that can build any Python object:

```python
document = yaml.load(
    await request.body(), Loader=yaml.Loader
)  # a YAML tag can name any function
```

### Why it matters

YAML has tags for Python objects. A document such as `!!python/object/apply:os.system ["id"]` makes the parser call `os.system` while it loads: the sender runs code on the server, as the server's user, before the application looks at the data. Any logged-in user of the import endpoint can do it.

### How to fix

Use the safe loader, which builds only plain data (strings, numbers, lists, mappings), and then validate the shape before using it:

```python
from pydantic import BaseModel


class ImportedTask(BaseModel):
    title: str
    description: str = ""


class ImportDocument(BaseModel):
    tasks: list[ImportedTask]


document = ImportDocument.model_validate(yaml.safe_load(await request.body()))
```

The same applies to `pickle`, `marshal` and `shelve` on data that does not come from you: do not use them for anything received.

### Checks

Semgrep at push time and in CI (it carries the blocking rule), Bandit B506 (reported, below the blocking threshold), SonarQube. The regression test posts a `!!python/object` payload and expects it to be rejected (WP4.5).

### References

- OWASP Top 10:2025: A08 Software or Data Integrity Failures
- CWE-502 Deserialization of Untrusted Data
- ASVS 5.0.0: 1.5.2 (deserialization of untrusted data uses safe handling, level 2), 2.2.1 (input is validated against an allow-list or an expected structure, level 1)

---

## NoSQL operator injection

**Rule:** `kairos.nosql-operator-injection` · not seeded: Kairos has no NoSQL store, so the rule ships with an annotated fixture only (`security/semgrep/tests/nosql-operator-injection.py`)

### The flaw

A value from the request goes straight into a MongoDB filter:

```python
user = users.find_one(request.json)  # the whole filter comes from the client
user = users.find_one(
    {"name": body["name"], "password": body["password"]}
)  # each value may be an object
```

### Why it matters

MongoDB filters are objects, and the keys that start with `$` are operators. If the client sends `{"name": "admin", "password": {"$ne": null}}`, the second condition means "password is not null", so the login succeeds without the password. `$where` is worse: its value is JavaScript run by the database. JSON makes this easy because the client chooses the type of every value.

### How to fix

Demand plain values. Validate the input against a schema in which the fields are strings, or convert them:

```python
class Login(BaseModel):
    name: str
    password: str


login = Login.model_validate(request.get_json())
user = users.find_one({"name": login.name})  # then compare the password hash in code
```

Never build `$where` from input; prefer the ordinary query operators. Do not let a client choose field names or operators.

### Checks

The Semgrep rule above at push time and in CI. The fixture marks each vulnerable line `ruleid` and each safe line `ok`, and `semgrep --test` proves both.

### References

- OWASP Top 10:2025: A05 Injection
- CWE-943 Improper Neutralization of Special Elements in Data Query Logic
- ASVS 5.0.0: 1.2.4 (database queries are protected against injection, level 1), 2.2.1 (input is validated, level 1)

---

## AI-assisted code

Code written with an assistant passes the same gates as any other code, and the gates do not know who wrote it. Two habits matter more than usual:

- **Check every dependency an assistant suggests** before adding it: the package must exist, be maintained, and be old enough to have been looked at (a name that sounds right and does not exist, or was registered last week by someone else, is a known attack: "slopsquatting"). The seven-day rule of this project applies.
- **Secrets never go into a prompt**, and neither does data that is not meant to leave the lab.

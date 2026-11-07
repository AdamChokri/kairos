## What and why

<!-- One or two sentences: what changes, and the reason. Link the work package or issue. -->

## Security checklist

Tick each line, or write "n/a" and why. A line left blank is a review comment.

- [ ] **New dependency?** Name, version and publisher are in the description; it is pinned in the lockfile; it was released at least 7 days ago (D-12); Dependabot and Trivy are quiet about it.
- [ ] **New or changed endpoint?** It requires authentication, it checks that the caller owns the object it reads or changes, and a test proves a second user is refused.
- [ ] **Input validated?** Every request field has a type and a length or range; nothing from a request reaches SQL, a shell command, a file path, `yaml.load` or `dangerouslySetInnerHTML` unchecked (see `docs/secure-coding.md`).
- [ ] **Secrets?** No credential, token, key or `.env` file in the diff, in a test or in a screenshot; a value the code needs comes from OpenBao or the environment.
- [ ] **Exceptions referenced?** A scanner finding that is accepted has an `EXC-NNNN` entry in `security/exceptions.yaml` (once WP4.4 creates it) with an owner and an expiry, and the tool's suppression marker names that ID; a silenced rule carries its reason in a comment.
- [ ] **The hooks ran** (`pre-commit run --all-files`, or the commit went through them) and the pipeline checks of this pull request are green.

## How it was tested

<!-- The commands you ran and what they showed. -->

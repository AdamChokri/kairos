# Evidence

Screenshots and exports for the evidence index (plan section 12.2), named `EV-NN-<short-name>.png`.

**File modes:** a screenshot saved from a Windows program has no Linux permissions and looks executable to Git (D-21). Before staging, from WSL2: `chmod 644 docs/evidence/*`.

**Before adding a file:** the repository is public. Crop or blur every token, password, unseal key share, webhook URL, private key and session cookie — a screenshot of a page that *could* show one gets checked twice. When in doubt, leave it out and describe it in the report instead.

**Work-package inputs:** a screenshot that a work package asks for by name, and that has no number in the evidence index, is stored as `wp<N.N>-<short-name>.png` (for example `wp2.3-as-is-jenkins-security.png`, `wp1.5-sonar-gate-assigned.png`). The same rules apply: no secret in the image, mode 644.

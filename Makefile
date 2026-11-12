# Kairos - local entry points. The sec-* targets (WP4.2) run the same scripts and the same pinned images as the pipeline.

.PHONY: lab-up lab-down lab-status as-is smoke check-seeded commit-scan-test measure dev-secrets dev-up dev-down \
        hooks-install hooks-commit hooks-push hooks-selftest rules-test \
        tools-check tools-pin sec-preflight sec-secrets sec-test sec-sast sec-sca sec-iac sec-image sec-all

# Lab power, from WSL2 on the Legion (plan section 14 and Appendix G).
lab-up:
	@bash infra/lab/lab-up.sh

lab-down:
	@bash infra/lab/lab-down.sh

lab-status:
	@bash infra/lab/lab-status.sh

# P2: the as-is practices on the build agent and the runtime hosts (WP2.2). Run a second time it
# must report changed=0; add -e as_is_state=absent to the command to remove them.
as-is:
	cd infra/ansible && ansible-playbook site.yml --tags as-is

# The Compose stack on the Legion (SV-01, SV-09, WP4.5): throwaway secret files first (never in Git), then the
# stack built from the working tree, the web tier on http://127.0.0.1:8080 and the API on http://127.0.0.1:8000.
# `make dev-down` also removes the database volume, because its password belongs to the files above.
COMPOSE_DEV = docker compose -f deploy/compose.yaml -f deploy/compose.dev.yaml

dev-secrets:
	@bash ci/tools/dev-secrets.sh

dev-up: dev-secrets
	GIT_SHA=$$(git rev-parse --short HEAD) $(COMPOSE_DEV) up --build -d --wait

dev-down:
	$(COMPOSE_DEV) down -v

# The API must be running: make smoke, or make smoke BASE=http://staging.kairos.lab:8000
BASE ?= http://localhost:8000

smoke:
	@bash ci/as-is/smoke.sh $(BASE)

check-seeded:
	@bash security/check-seeded.sh $(BASE)

commit-scan-test:
	@bash ci/tools/test-commit-scan.sh

# WP2.3: rewrites docs/as-is/measurements.md from the lab.
measure:
	@bash ci/as-is/measure.sh

# P3: the developer workstation (WP3.2, WP3.3). hooks-install (WP4.6) installs pre-commit with uv and builds the hook
# environments under the 7-day rule (HOOK-01, D-34); semgrep comes from `uv tool install`.
# Until WP4.5 fixes the seeded weaknesses, hooks-commit reports bandit and eslint on them, on purpose.
hooks-install:
	@bash ci/tools/hooks-install.sh

hooks-commit:
	pre-commit run --all-files

hooks-push:
	pre-commit run --all-files --hook-stage pre-push

# The hook scripts proved without the network: the commit-time scan and the Trivy wrapper.
hooks-selftest:
	@bash ci/tools/test-commit-scan.sh
	@bash ci/tools/test-hook-trivy.sh
	@bash ci/tools/test-ci-scripts.sh

# WP3.3 done-when: every rule passes its annotated tests and links to a section of docs/secure-coding.md.
rules-test:
	semgrep --test --metrics off --config security/semgrep/ security/semgrep/tests/
	@bash ci/tools/check-rule-links.sh
	@semgrep --metrics off --quiet --error --config security/semgrep/llm-context-unscoped.yaml security/semgrep/tests/llm-context-unscoped-no-model.py && echo 'ok    a module that talks to no model is not flagged by kairos.llm-context-unscoped'

# P4: the pipeline's controls, run locally (WP4.2). Each target runs the script that Jenkins runs. Exit code 2 of a
# script means "would block, the control is in report mode" (yellow in Jenkins): make reports it and goes on.
# Run sec-secrets BEFORE sec-test (sec-test installs node_modules and .venv, which Gitleaks would read), and
# sec-sast after it. Needs Docker running (sudo service docker start), curl, python3 and, for preflight, PyYAML.
define RUN_CONTROL
	@bash ci/scripts/$(1).sh; rc=$$?; if [ $$rc -eq 2 ]; then echo "$(1): would block (report mode): yellow in Jenkins"; elif [ $$rc -ne 0 ]; then exit $$rc; fi
endef

tools-check:
	@bash ci/tools/check-tools-lock.sh
	@bash ci/tools/pin-tools.sh --check

tools-pin:
	@bash ci/tools/pin-tools.sh

sec-preflight:
	$(call RUN_CONTROL,preflight)

sec-secrets:
	$(call RUN_CONTROL,secrets_scan)

sec-test:
	$(call RUN_CONTROL,build_test)

sec-sast:
	$(call RUN_CONTROL,sast)

sec-sca:
	$(call RUN_CONTROL,sca)

sec-iac:
	$(call RUN_CONTROL,iac)

# Builds both images, scans the saved files, then removes the images and files again.
sec-image:
	@bash ci/scripts/build_images.sh
	$(call RUN_CONTROL,image_scan)
	@bash ci/scripts/build_images.sh --cleanup

sec-all: sec-preflight sec-secrets sec-test sec-sast sec-sca sec-iac sec-image

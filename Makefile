# Kairos - local entry points. WP4.2 adds the sec-* targets (the same scripts and images as CI).

.PHONY: lab-up lab-down lab-status as-is smoke check-seeded commit-scan-test measure

# Lab power, from WSL2 on the Legion (plan section 14 and Appendix G).
lab-up:
	@bash infra/lab/lab-up.sh

lab-down:
	@bash infra/lab/lab-down.sh

lab-status:
	@bash infra/lab/lab-status.sh

# P2: the as-is practices on the build agent and the runtime hosts (WP2.2). Run a second time it
# must report changed=0; add -e as_is_state=absent to the command to remove them (WP5.3, WP6.1).
as-is:
	cd infra/ansible && ansible-playbook site.yml --tags as-is

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

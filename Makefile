# Kairos - local entry points. WP4.2 adds the sec-* targets (the same scripts and images as CI).

.PHONY: lab-up lab-down lab-status

# Lab power, from WSL2 on the Legion (plan section 14 and Appendix G).
lab-up:
	@bash infra/lab/lab-up.sh

lab-down:
	@bash infra/lab/lab-down.sh

lab-status:
	@bash infra/lab/lab-status.sh

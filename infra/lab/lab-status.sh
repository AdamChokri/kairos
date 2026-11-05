#!/usr/bin/env bash
# infra/lab/lab-status.sh - prints the state of every lab VM, its SSH port and OpenBao's
# seal status (make lab-status, from WSL2). Changes nothing.
set -Eeuo pipefail
# shellcheck source=lablib.sh
source "$(dirname "$(readlink -f "$0")")/lablib.sh"

lab_init
lab_print_status

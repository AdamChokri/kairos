#!/usr/bin/env bash
# infra/pki/make-ca.sh - creates the Kairos lab CA once (plan WP1.1, D-16).
# The private key stays in ~/.kairos-pki (0700), encrypted with a passphrase you keep in your
# password manager; only the certificate enters the repository, as infra/pki/kairos-lab-ca.crt.
# The CA can issue nothing but leaf certificates (pathlen 0) and only for names under kairos.lab
# and addresses in 192.168.1.0/24 (name constraints), so a stolen CA key cannot impersonate
# any other site - even on the machines that trust it.
# Refuses to run if a CA key already exists: there is one lab CA, rotated only at project end.
# A run that fails (a passphrase refused, an interrupted prompt) removes the key and certificate it
# was creating, so it can simply be run again (E-17).
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKI="${KAIROS_PKI:-$HOME/.kairos-pki}"
CA_KEY="$PKI/kairos-lab-ca.key"
CA_CRT="$DIR/kairos-lab-ca.crt"
DAYS=1095   # 3 years: longer than the project, short enough to force a renewal decision

command -v openssl >/dev/null 2>&1 || { echo "ERROR: missing tool: openssl" >&2; exit 1; }
[[ -e $CA_KEY ]] && { echo "ERROR: $CA_KEY already exists - the lab CA is created once" >&2; exit 1; }

crt_existed=no
[[ -e $CA_CRT ]] && crt_existed=yes
completed=no
cnf=''
cleanup() {
  [[ -n $cnf ]] && rm -f "$cnf"
  if [[ $completed != yes ]]; then
    rm -f "$CA_KEY"
    [[ $crt_existed == yes ]] || rm -f "$CA_CRT"
    echo "make-ca.sh did not complete: nothing was kept - run it again" >&2
  fi
}
trap cleanup EXIT

umask 077
mkdir -p "$PKI/issued"
chmod 700 "$PKI" "$PKI/issued"

cnf=$(mktemp)
cat > "$cnf" <<'CNF'
[req]
distinguished_name = dn
prompt             = no
x509_extensions    = v3_ca
[dn]
O  = Kairos lab
CN = Kairos Lab CA
[v3_ca]
basicConstraints       = critical, CA:true, pathlen:0
keyUsage               = critical, keyCertSign, cRLSign
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid:always
nameConstraints        = critical, permitted;DNS:kairos.lab, permitted;IP:192.168.1.0/255.255.255.0
CNF

echo "Choose the CA key passphrase now (keep it in your safe place first; at least 4 characters)."
openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -aes-256-cbc -out "$CA_KEY"
openssl req -new -x509 -sha256 -days "$DAYS" -key "$CA_KEY" -config "$cnf" -out "$CA_CRT"
chmod 600 "$CA_KEY"
chmod 644 "$CA_CRT"
completed=yes

echo "CA key:         $CA_KEY (never copy it into the repository)"
echo "CA certificate: $CA_CRT"
openssl x509 -in "$CA_CRT" -noout -subject -enddate -fingerprint -sha256

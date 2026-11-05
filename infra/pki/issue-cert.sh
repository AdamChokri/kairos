#!/usr/bin/env bash
# infra/pki/issue-cert.sh NAME IP [NAME...] - issues a TLS server certificate from the lab CA.
#   NAME  the main DNS name, under kairos.lab (also the subject CN)
#   IP    the server's address, under 192.168.1.0/24
#   more  extra DNS names under kairos.lab
# Writes ~/.kairos-pki/issued/NAME.key (0600, unencrypted: a service reads it at start) and
# NAME.crt. Valid 397 days, the ceiling browsers accept for server certificates. Re-running it for
# the same name issues a new key and certificate (renewal); the old pair is kept as *.old.
# A run that does not complete (a refused CA passphrase) removes the key it created and puts the
# previous pair back, so nothing is left half-done and it can simply be run again (E-22).
# Example: infra/pki/issue-cert.sh openbao.kairos.lab 192.168.1.70
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKI="${KAIROS_PKI:-$HOME/.kairos-pki}"
CA_KEY="$PKI/kairos-lab-ca.key"
CA_CRT="$DIR/kairos-lab-ca.crt"
DAYS=397

[[ $# -ge 2 ]] || { echo "usage: $0 NAME IP [EXTRA-NAME...]" >&2; exit 2; }
name=$1 ip=$2; shift 2
[[ $name =~ ^[a-z0-9-]+(\.[a-z0-9-]+)*\.kairos\.lab$ ]] || { echo "ERROR: $name is not under kairos.lab" >&2; exit 2; }
[[ $ip =~ ^192\.168\.1\.[0-9]{1,3}$ ]] || { echo "ERROR: $ip is not in 192.168.1.0/24" >&2; exit 2; }
for extra in "$@"; do
  [[ $extra =~ ^[a-z0-9-]+(\.[a-z0-9-]+)*\.kairos\.lab$ ]] || { echo "ERROR: $extra is not under kairos.lab" >&2; exit 2; }
done
[[ -r $CA_KEY && -r $CA_CRT ]] || { echo "ERROR: lab CA missing - run infra/pki/make-ca.sh first" >&2; exit 1; }

umask 077
out="$PKI/issued/$name"
completed=no moved=() ext='' csr=''
cleanup() {
  [[ -n $ext ]] && rm -f "$ext"
  [[ -n $csr ]] && rm -f "$csr"
  if [[ $completed != yes ]]; then
    rm -f "$out.key" "$out.crt"
    local f
    for f in "${moved[@]}"; do mv -f "$f.old" "$f"; done
    echo "issue-cert.sh did not complete: nothing was changed - run it again" >&2
  fi
}
trap cleanup EXIT
for f in "$out.key" "$out.crt"; do
  if [[ -e $f ]]; then mv -f "$f" "$f.old"; moved+=("$f"); fi
done

san="DNS:$name,IP:$ip"
for extra in "$@"; do san+=",DNS:$extra"; done

ext=$(mktemp); csr=$(mktemp)
printf '%s\n' \
  "basicConstraints = critical, CA:false" \
  "keyUsage = critical, digitalSignature" \
  "extendedKeyUsage = serverAuth" \
  "subjectKeyIdentifier = hash" \
  "authorityKeyIdentifier = keyid" \
  "subjectAltName = $san" > "$ext"

openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$out.key"
openssl req -new -sha256 -key "$out.key" -subj "/O=Kairos lab/CN=$name" -out "$csr"
echo "Signing with the lab CA (enter the CA key passphrase):"
openssl x509 -req -sha256 -days "$DAYS" -in "$csr" -CA "$CA_CRT" -CAkey "$CA_KEY" \
  -CAcreateserial -CAserial "$PKI/kairos-lab-ca.srl" -extfile "$ext" -out "$out.crt"
chmod 600 "$out.key"
chmod 644 "$out.crt"

openssl verify -CAfile "$CA_CRT" "$out.crt"
completed=yes
openssl x509 -in "$out.crt" -noout -subject -enddate -ext subjectAltName

# infra/openbao/policies/jenkins-signer.hcl - AppRole jenkins-signer (Jenkins credential bao-signer).
# Sign and verify with the Transit key kairos-images and read its public half - never export it
# (the key is created non-exportable by apply.sh, plan D-14).
path "transit/sign/kairos-images" {
  capabilities = ["update"]
}
path "transit/sign/kairos-images/*" {
  capabilities = ["update"]
}
path "transit/verify/kairos-images" {
  capabilities = ["update"]
}
path "transit/verify/kairos-images/*" {
  capabilities = ["update"]
}
path "transit/keys/kairos-images" {
  capabilities = ["read"]
}

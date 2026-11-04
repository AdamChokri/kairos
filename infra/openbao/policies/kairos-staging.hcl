# infra/openbao/policies/kairos-staging.hcl - AppRole kairos-staging (OpenBao Agent on dso-staging).
# The staging runtime secrets: database password, JWT key, and the DeepSeek key (D-20).
path "kv/data/kairos/staging" {
  capabilities = ["read"]
}
path "kv/data/kairos/staging/llm" {
  capabilities = ["read"]
}

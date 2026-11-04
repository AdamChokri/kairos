# infra/openbao/policies/kairos-prod.hcl - AppRole kairos-prod (OpenBao Agent on dso-prod).
# The production runtime secrets: database password, JWT key, and the DeepSeek key (D-20).
path "kv/data/kairos/prod" {
  capabilities = ["read"]
}
path "kv/data/kairos/prod/llm" {
  capabilities = ["read"]
}

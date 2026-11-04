# infra/openbao/policies/jenkins-deploy.hcl - AppRole jenkins-deploy (Jenkins credential bao-deploy).
# The SSH deploy keys of staging and production.
path "kv/data/ci/deploy-staging" {
  capabilities = ["read"]
}
path "kv/data/ci/deploy-prod" {
  capabilities = ["read"]
}

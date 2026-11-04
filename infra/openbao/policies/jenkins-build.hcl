# infra/openbao/policies/jenkins-build.hcl - AppRole jenkins-build (Jenkins credential bao-build).
# The build lane's secrets: the SonarQube analysis token and the Docker Hub read & write token.
path "kv/data/ci/sonarqube" {
  capabilities = ["read"]
}
path "kv/data/ci/dockerhub" {
  capabilities = ["read"]
}

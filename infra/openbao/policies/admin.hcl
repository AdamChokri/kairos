# infra/openbao/policies/admin.hcl - the userpass administrator "adam", who replaces the
# root token once setup is done (plan D-07). Every action stays in the audit log under this name.
path "*" {
  capabilities = ["create", "read", "update", "patch", "delete", "list", "sudo"]
}

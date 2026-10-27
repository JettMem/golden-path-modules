# A golden-path project's production on Azure

A project uses it from its own `infra/production/main.tf`, and an engineer applies it at a terminal, signed in as
themselves, from a plan they read. The JettMem factory then releases into it.

It makes one resource group, `<project>-production`, with:

| What | Name | Why |
|---|---|---|
| Container Apps environment | `<project>-production` | Consumption only: no fixed cost |
| Container Apps environment for previews | `<project>-previews` | The factory makes each preview's apps here |
| Container registry (Basic, no admin user) | `var.registry` | The factory builds each release's image here (`web:r12`) |
| Log workspace | `<project>-production-logs` | 30 days, at most 1 GB a day |
| Identity | `<project>-production-apps` | What the apps and the migrations run as: AcrPull, and Key Vault Secrets User |
| Vault | `<project>-production-<hash>` | The apps' secrets, read as Key Vault references, never plain settings |
| One Container App per app | `<project>-<app>` | Multiple-revision mode, ten old revisions kept to roll back to |
| Migrations job, if `migrations` is set | `<project>-migrate` | Run once per release from its image |

The factory releases into it with its deploy identity: each app's image, its revision's suffix and its traffic are the
factory's, and the module ignores them (`lifecycle.ignore_changes`). Everything is tagged `managed-by:
jettmem-factory`.

## Inputs

| Name | Type | Default |
|---|---|---|
| `project` | string: the project's key, three lower-case letters (`sta`) | required |
| `registry` | string: the registry's name, 5 to 50 lower-case letters and digits, unique in all of Azure | required |
| `apps` | `map(object({ port = number, health = string, cpu = optional(number, 0.25), memory = optional(string, "0.5Gi") }))` | required |
| `location` | string | `"eastus2"` |
| `migrations` | `list(string)`: the command that runs the migrations from the release's image | `null` (none) |
| `database_secret` | bool: whether the apps and the migrations get `DATABASE_URL` from the vault | `false` |

## Outputs

What an engineer records on the project's page in the factory (Production → Record production). A root stack should
output every one of them.

| Name | Value |
|---|---|
| `resource_group` | The resource group's name |
| `registry` | The registry's name |
| `apps` | Each app's `{ container_app, address, health }`, by its name |
| `migrations_job` | The migrations job's name, or `null` without `migrations` |
| `vault` | The vault's name |
| `previews_environment` | The previews' environment's name |
| `apps_identity` | The apps' identity's name |

## Using it

In the project's `infra/production/main.tf`, pinned to a full commit of this repository:

```hcl
module "production" {
  source   = "git::https://github.com/JettMem/golden-path-modules.git//modules/azure-production?ref=<commit>"
  project  = "sta"
  registry = "stastatusprod"
  apps     = { web = { port = 3000, health = "/health" } }
}
```

With a database: `migrations = ["node", "src/migrate.ts"]` and, once its connection string is in the vault,
`database_secret = true`. The connection string is stored at a hidden prompt, never in code, arguments or state:

On macOS:

```
printf 'Paste the connection string (it will not show), then press Enter: '; read -rs value; echo
printf '%s' "$value" | az keyvault secret set --vault-name <vault> --name database-url --value @- --output none
unset value
```

On Windows, in PowerShell:

```
$value = Read-Host -AsSecureString "Paste the connection string (it will not show), then press Enter"
[System.Net.NetworkCredential]::new('', $value).Password | az keyvault secret set --vault-name <vault> --name database-url --value '@-' --output none
Remove-Variable value
```

From azurerm 5.9.0's documentation, checked with `tofu validate`, not yet applied: the Key Vault reference on a Container
App's secret (`key_vault_secret_id` with `identity`), and `ignore_changes` on nested blocks' attributes.

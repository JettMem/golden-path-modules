# JettMem golden-path modules

OpenTofu modules that JettMem golden-path projects use from their own `infra/`. They're public so that `tofu init` can
fetch them without credentials, on an engineer's computer or on a runner. Nothing here is secret, and nothing secret
may ever be added: no keys, ids, state or connection strings.

| Module | What it makes |
|---|---|
| [`modules/azure-production`](modules/azure-production) | A project's production on Azure, and where its previews run |

Use a module pinned to a full commit of this repository, never a branch:

```hcl
module "production" {
  source = "git::https://github.com/JettMem/golden-path-modules.git//modules/azure-production?ref=<40-character commit>"
  # …
}
```

Each pull request is checked with OpenTofu 1.13.1: `tofu fmt -check` and `tofu validate` on every module.

# terraform-aws-backup

Terraform module that manages [AWS
Backup](https://aws.amazon.com/backup/) resources. It creates a backup vault
and a backup plan whose rules are rendered from a list variable, giving a single
place to define scheduled, retained backups.

## Usage

```hcl
module "backup" {
  source = "github.com/moveeeax/terraform-aws-backup"

  vault_name = "prod-vault"
  plan_name  = "prod-plan"

  rules = [
    {
      rule_name    = "daily"
      schedule     = "cron(0 5 * * ? *)"
      delete_after = 30
    }
  ]

  tags = {
    Environment = "production"
    ManagedBy   = "terraform"
  }
}
```

A runnable example lives in [`examples/basic`](examples/basic).

### Cold storage

A rule may transition recovery points to cold storage before deleting them.
AWS Backup keeps a recovery point in cold storage for a minimum of 90 days, so
`delete_after` must be at least `cold_storage_after + 90`:

```hcl
rules = [
  {
    rule_name          = "monthly"
    schedule           = "cron(0 5 1 * ? *)"
    cold_storage_after = 30
    delete_after       = 120 # 30 + 90
  }
]
```

### Rule validation

The module validates rules at plan time so that a mistake surfaces before
`CreateBackupPlan` rejects it mid-apply:

- `rules` must be non-empty and every `rule_name` must be unique.
- `schedule` must be a six-field `cron(...)` or a `rate(...)` expression.
  Five-field UNIX cron such as `cron(0 5 * * ?)` is rejected.
- In a `cron(...)` expression at least one of day-of-month (field 3) and
  day-of-week (field 5) must be `?`. AWS cannot evaluate both at once, so
  `cron(0 5 * * * *)` — five-field UNIX cron with a year appended — is
  rejected. Use `cron(0 5 * * ? *)` for daily or `cron(0 5 ? * MON *)` for
  weekly.
- `start_window` must be at least 60 minutes and `completion_window` must be
  greater than `start_window`.
- `cold_storage_after`, when set, must be at least 1 and `delete_after` must be
  at least `cold_storage_after + 90`.

## Requirements

| Name      | Version  |
|-----------|----------|
| terraform | >= 1.5   |
| aws       | >= 5.0   |

## Inputs

| Name          | Description                                             | Type                | Default   | Required |
|---------------|---------------------------------------------------------|---------------------|-----------|:--------:|
| `vault_name`  | Name of the backup vault.                               | `string`            | n/a       |   yes    |
| `kms_key_arn` | ARN of the KMS key used to encrypt backups.             | `string`            | `null`    |    no    |
| `plan_name`   | Name of the backup plan.                                | `string`            | n/a       |   yes    |
| `rules`       | List of backup rules that make up the plan.             | `list(object(...))` | n/a       |   yes    |
| `tags`        | Tags applied to the vault and plan.                     | `map(string)`       | `{}`      |    no    |

## Outputs

| Name           | Description                                        |
|----------------|----------------------------------------------------|
| `vault_id`     | Name of the backup vault.                          |
| `vault_arn`    | ARN of the backup vault.                           |
| `plan_id`      | ID of the backup plan.                             |
| `plan_arn`     | ARN of the backup plan.                            |
| `plan_version` | Unique version identifier of the backup plan.      |

## Development

```sh
terraform fmt -recursive
terraform init -backend=false && terraform validate
terraform test          # requires Terraform >= 1.7 for mock_provider
tflint --recursive
```

`tests/` uses `mock_provider "aws" {}`, so the suite runs with no AWS
credentials and no network. The module's own `required_version` stays at
`>= 1.5`; only the test suite needs 1.7.

## License

[MIT](LICENSE)

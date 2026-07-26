variable "vault_name" {
  description = "Name of the backup vault."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{2,50}$", var.vault_name))
    error_message = "vault_name must be 2-50 characters and contain only letters, numbers, hyphens and underscores. AWS Backup rejects any other character (including periods, which are allowed in plan and rule names but not vault names) when creating the vault."
  }
}

variable "kms_key_arn" {
  description = "ARN of the KMS key used to encrypt backups in the vault. Null uses the default key."
  type        = string
  default     = null
}

variable "plan_name" {
  description = "Name of the backup plan."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9_.-]{1,50}$", var.plan_name))
    error_message = "plan_name must be 1-50 characters and contain only letters, numbers, hyphens, underscores and periods; AWS Backup rejects any other character."
  }
}

variable "rules" {
  description = <<-EOT
    List of backup rules that make up the plan.

    * `rule_name` must be 1-50 characters: letters, numbers, hyphens,
      underscores and periods only.
    * `schedule` must be an AWS schedule expression: a six-field `cron(min hour
      day-of-month month day-of-week year)` or `rate(value unit)`. Five-field
      UNIX cron is rejected by AWS.
    * In a `cron()` expression at least one of day-of-month and day-of-week
      must be `?`. AWS cannot honour both at once and rejects, for example,
      `cron(0 5 * * * *)`.
    * In a `rate()` expression the unit must be singular when the value is 1
      (`rate(1 hour)`) and plural otherwise (`rate(5 hours)`). AWS rejects the
      mismatched forms `rate(1 hours)` and `rate(5 hour)`.
    * `start_window` is in minutes and must be at least 60.
    * `completion_window` is in minutes and must be greater than `start_window`.
    * `cold_storage_after` is optional. When set, `delete_after` must be at
      least `cold_storage_after + 90`, because AWS Backup keeps a recovery
      point in cold storage for a minimum of 90 days.
  EOT
  type = list(object({
    rule_name          = string
    schedule           = string
    start_window       = optional(number, 60)
    completion_window  = optional(number, 180)
    delete_after       = optional(number, 30)
    cold_storage_after = optional(number, null)
  }))

  validation {
    condition     = length(var.rules) > 0
    error_message = "At least one backup rule must be provided."
  }

  validation {
    condition     = length(distinct([for r in var.rules : r.rule_name])) == length(var.rules)
    error_message = "Each rule_name must be unique within a backup plan."
  }

  validation {
    condition = alltrue([
      for r in var.rules : can(regex("^[a-zA-Z0-9_.-]{1,50}$", r.rule_name))
    ])
    error_message = "Each rule_name must be 1-50 characters and contain only letters, numbers, hyphens, underscores and periods; AWS Backup rejects any other character."
  }

  # The rate() alternatives are split by value so that unit agreement can be
  # enforced: AWS requires a singular unit only when the value is exactly 1
  # ("rate(1 hour)") and a plural unit for every other value ("rate(5 hours)").
  # A single combined character class can't express that distinction, and the
  # mismatched forms ("rate(1 hours)", "rate(5 hour)") pass CreateBackupPlan
  # request validation only to be rejected by the service itself.
  validation {
    condition = alltrue([
      for r in var.rules :
      can(regex("^cron\\([^ )]+( [^ )]+){5}\\)$", r.schedule)) ||
      can(regex("^rate\\(1 (minute|hour|day)\\)$", r.schedule)) ||
      can(regex("^rate\\((?:[2-9][0-9]*|1[0-9]+) (minutes|hours|days)\\)$", r.schedule))
    ])
    error_message = "Each schedule must be a six-field cron() expression such as \"cron(0 5 * * ? *)\" or a rate() expression such as \"rate(12 hours)\". In rate(), the unit must be singular when the value is 1 (\"rate(1 hour)\") and plural otherwise (\"rate(5 hours)\")."
  }

  # AWS cannot evaluate day-of-month and day-of-week at the same time, so one of
  # them has to be "?". The AWS provider does not catch this — it surfaces only
  # when CreateBackupPlan rejects the schedule mid-apply. Appending a year field
  # to a five-field UNIX cron produces exactly this shape, e.g. cron(0 5 * * * *).
  validation {
    condition = alltrue([
      for r in var.rules :
      !can(regex("^cron\\(", r.schedule)) ||
      can(regex("^cron\\([^ )]+ [^ )]+ \\? [^ )]+ [^ )]+ [^ )]+\\)$", r.schedule)) ||
      can(regex("^cron\\([^ )]+ [^ )]+ [^ )]+ [^ )]+ \\? [^ )]+\\)$", r.schedule))
    ])
    error_message = "In a cron() schedule at least one of day-of-month (field 3) and day-of-week (field 5) must be \"?\". AWS rejects expressions such as \"cron(0 5 * * * *)\"; use \"cron(0 5 * * ? *)\" to run every day, or \"cron(0 5 ? * MON *)\" to run every Monday."
  }

  validation {
    condition     = alltrue([for r in var.rules : r.start_window >= 60])
    error_message = "start_window must be at least 60 minutes; AWS Backup rejects shorter backup windows."
  }

  validation {
    condition     = alltrue([for r in var.rules : r.completion_window > r.start_window])
    error_message = "completion_window must be greater than start_window."
  }

  validation {
    condition     = alltrue([for r in var.rules : r.delete_after == null || r.delete_after >= 1])
    error_message = "delete_after must be at least 1 day when set."
  }

  validation {
    condition = alltrue([
      for r in var.rules :
      r.cold_storage_after == null || r.cold_storage_after >= 1
    ])
    error_message = "cold_storage_after must be at least 1 day when set."
  }

  validation {
    condition = alltrue([
      for r in var.rules :
      r.cold_storage_after == null || (r.delete_after != null && r.delete_after >= r.cold_storage_after + 90)
    ])
    error_message = "When cold_storage_after is set, delete_after must be at least cold_storage_after + 90 days. AWS Backup enforces a 90 day minimum in cold storage and rejects the plan at apply time otherwise."
  }
}

variable "tags" {
  description = "Tags applied to the vault and plan."
  type        = map(string)
  default     = {}
}

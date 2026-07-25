variable "vault_name" {
  description = "Name of the backup vault."
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of the KMS key used to encrypt backups in the vault. Null uses the default key."
  type        = string
  default     = null
}

variable "plan_name" {
  description = "Name of the backup plan."
  type        = string
}

variable "rules" {
  description = <<-EOT
    List of backup rules that make up the plan.

    * `schedule` must be an AWS schedule expression: a six-field `cron(min hour
      day-of-month month day-of-week year)` or `rate(value unit)`. Five-field
      UNIX cron is rejected by AWS.
    * In a `cron()` expression at least one of day-of-month and day-of-week
      must be `?`. AWS cannot honour both at once and rejects, for example,
      `cron(0 5 * * * *)`.
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
      for r in var.rules :
      can(regex("^cron\\([^ )]+( [^ )]+){5}\\)$", r.schedule)) ||
      can(regex("^rate\\([1-9][0-9]* (minute|minutes|hour|hours|day|days)\\)$", r.schedule))
    ])
    error_message = "Each schedule must be a six-field cron() expression such as \"cron(0 5 * * ? *)\" or a rate() expression such as \"rate(12 hours)\"."
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

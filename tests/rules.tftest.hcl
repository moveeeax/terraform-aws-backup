# Test-only requirement: `mock_provider` needs Terraform/OpenTofu >= 1.7.
# The module itself still supports >= 1.5 (see versions.tf) — do not bump it.
mock_provider "aws" {}

variables {
  vault_name = "test-vault"
  plan_name  = "test-plan"
  rules = [
    {
      rule_name = "daily"
      schedule  = "cron(0 5 * * ? *)"
    }
  ]
}

run "defaults_are_applied" {
  command = plan

  assert {
    condition     = aws_backup_vault.this.name == "test-vault"
    error_message = "Vault name should come straight from var.vault_name."
  }

  assert {
    condition     = length(aws_backup_plan.this.rule) == 1
    error_message = "One input rule should render exactly one plan rule."
  }

  assert {
    condition     = one(aws_backup_plan.this.rule).target_vault_name == "test-vault"
    error_message = "Every rule must target the vault this module creates."
  }

  assert {
    condition     = one(aws_backup_plan.this.rule).start_window == 60
    error_message = "start_window should default to 60 minutes."
  }

  assert {
    condition     = one(aws_backup_plan.this.rule).completion_window == 180
    error_message = "completion_window should default to 180 minutes."
  }

  assert {
    condition     = one(one(aws_backup_plan.this.rule).lifecycle).delete_after == 30
    error_message = "delete_after should default to 30 days."
  }
}

run "cold_storage_with_valid_gap_is_accepted" {
  command = plan

  variables {
    rules = [
      {
        rule_name          = "monthly"
        schedule           = "cron(0 5 1 * ? *)"
        cold_storage_after = 30
        delete_after       = 120
      }
    ]
  }

  assert {
    condition     = one(one(aws_backup_plan.this.rule).lifecycle).cold_storage_after == 30
    error_message = "cold_storage_after should be passed through to the rule lifecycle."
  }

  assert {
    condition     = one(one(aws_backup_plan.this.rule).lifecycle).delete_after == 120
    error_message = "delete_after should be passed through to the rule lifecycle."
  }
}

run "rate_schedules_are_accepted" {
  command = plan

  variables {
    rules = [
      {
        rule_name = "twice-daily"
        schedule  = "rate(12 hours)"
      }
    ]
  }

  assert {
    condition     = one(aws_backup_plan.this.rule).schedule == "rate(12 hours)"
    error_message = "rate() schedules should be passed through unchanged."
  }
}

run "rejects_empty_rules" {
  command = plan

  variables {
    rules = []
  }

  expect_failures = [var.rules]
}

run "rejects_duplicate_rule_names" {
  command = plan

  variables {
    rules = [
      { rule_name = "daily", schedule = "cron(0 5 * * ? *)" },
      { rule_name = "daily", schedule = "cron(0 17 * * ? *)" },
    ]
  }

  expect_failures = [var.rules]
}

# Five-field UNIX cron is the classic mistake here: AWS requires six fields.
run "rejects_five_field_unix_cron" {
  command = plan

  variables {
    rules = [
      { rule_name = "daily", schedule = "cron(0 5 * * ?)" },
    ]
  }

  expect_failures = [var.rules]
}

# A cron() schedule may pin day-of-week instead of day-of-month, as long as the
# other field is "?".
run "day_of_week_schedules_are_accepted" {
  command = plan

  variables {
    rules = [
      { rule_name = "weekly", schedule = "cron(0 5 ? * MON *)" },
    ]
  }

  assert {
    condition     = one(aws_backup_plan.this.rule).schedule == "cron(0 5 ? * MON *)"
    error_message = "A cron() schedule that pins day-of-week should be accepted unchanged."
  }
}

# Appending a year field to five-field UNIX cron yields six fields with "*" in
# both day-of-month and day-of-week. AWS cannot honour both and rejects the plan
# at CreateBackupPlan time, so it must be caught here instead.
run "rejects_cron_without_question_mark_day_field" {
  command = plan

  variables {
    rules = [
      { rule_name = "daily", schedule = "cron(0 5 * * * *)" },
    ]
  }

  expect_failures = [var.rules]
}

run "rejects_cron_with_two_concrete_day_fields" {
  command = plan

  variables {
    rules = [
      { rule_name = "daily", schedule = "cron(0 5 1 * MON *)" },
    ]
  }

  expect_failures = [var.rules]
}

run "rejects_non_schedule_expression" {
  command = plan

  variables {
    rules = [
      { rule_name = "daily", schedule = "0 5 * * ? *" },
    ]
  }

  expect_failures = [var.rules]
}

run "rejects_start_window_below_60" {
  command = plan

  variables {
    rules = [
      { rule_name = "daily", schedule = "cron(0 5 * * ? *)", start_window = 30 },
    ]
  }

  expect_failures = [var.rules]
}

run "rejects_completion_window_not_greater_than_start_window" {
  command = plan

  variables {
    rules = [
      { rule_name = "daily", schedule = "cron(0 5 * * ? *)", start_window = 180, completion_window = 180 },
    ]
  }

  expect_failures = [var.rules]
}

# AWS Backup keeps recovery points in cold storage for at least 90 days, so
# delete_after must be >= cold_storage_after + 90. Without this validation the
# plan applies cleanly against the API only to fail at CreateBackupPlan time.
run "rejects_cold_storage_without_90_day_gap" {
  command = plan

  variables {
    rules = [
      {
        rule_name          = "monthly"
        schedule           = "cron(0 5 1 * ? *)"
        cold_storage_after = 30
        delete_after       = 100
      },
    ]
  }

  expect_failures = [var.rules]
}

run "rejects_cold_storage_without_delete_after" {
  command = plan

  variables {
    rules = [
      {
        rule_name          = "monthly"
        schedule           = "cron(0 5 1 * ? *)"
        cold_storage_after = 30
        delete_after       = null
      },
    ]
  }

  expect_failures = [var.rules]
}

run "rejects_zero_cold_storage_after" {
  command = plan

  variables {
    rules = [
      {
        rule_name          = "monthly"
        schedule           = "cron(0 5 1 * ? *)"
        cold_storage_after = 0
        delete_after       = 365
      },
    ]
  }

  expect_failures = [var.rules]
}

# AWS requires a singular unit only when the rate() value is exactly 1.
run "accepts_singular_rate_with_value_one" {
  command = plan

  variables {
    rules = [
      { rule_name = "hourly", schedule = "rate(1 hour)" },
    ]
  }

  assert {
    condition     = one(aws_backup_plan.this.rule).schedule == "rate(1 hour)"
    error_message = "rate(1 hour) should be accepted unchanged."
  }
}

run "rejects_plural_rate_with_value_one" {
  command = plan

  variables {
    rules = [
      { rule_name = "hourly", schedule = "rate(1 hours)" },
    ]
  }

  expect_failures = [var.rules]
}

run "rejects_singular_rate_with_value_greater_than_one" {
  command = plan

  variables {
    rules = [
      { rule_name = "daily", schedule = "rate(5 hour)" },
    ]
  }

  expect_failures = [var.rules]
}

run "accepts_plural_rate_with_two_digit_value" {
  command = plan

  variables {
    rules = [
      { rule_name = "twice-daily", schedule = "rate(10 hours)" },
    ]
  }

  assert {
    condition     = one(aws_backup_plan.this.rule).schedule == "rate(10 hours)"
    error_message = "rate(10 hours) should be accepted unchanged."
  }
}

run "rejects_rule_name_with_invalid_characters" {
  command = plan

  variables {
    rules = [
      { rule_name = "daily backup!", schedule = "cron(0 5 * * ? *)" },
    ]
  }

  expect_failures = [var.rules]
}

run "rejects_rule_name_too_long" {
  command = plan

  variables {
    rules = [
      { rule_name = join("", [for i in range(51) : "a"]), schedule = "cron(0 5 * * ? *)" },
    ]
  }

  expect_failures = [var.rules]
}

run "rejects_vault_name_too_short" {
  command = plan

  variables {
    vault_name = "a"
  }

  expect_failures = [var.vault_name]
}

run "rejects_vault_name_with_period" {
  command = plan

  variables {
    vault_name = "prod.vault"
  }

  expect_failures = [var.vault_name]
}

run "rejects_plan_name_with_invalid_characters" {
  command = plan

  variables {
    plan_name = "prod plan"
  }

  expect_failures = [var.plan_name]
}

run "new_rule_arguments_default_to_off" {
  command = plan

  assert {
    condition     = one(aws_backup_plan.this.rule).enable_continuous_backup == false
    error_message = "enable_continuous_backup should default to false."
  }

  assert {
    condition     = length(one(aws_backup_plan.this.rule).copy_action) == 0
    error_message = "A rule without copy_actions should render no copy_action blocks."
  }

  assert {
    condition     = one(aws_backup_plan.this.rule).schedule_expression_timezone == null
    error_message = "schedule_expression_timezone should stay null so AWS applies its Etc/UTC default."
  }
}

run "copy_action_with_lifecycle_is_rendered" {
  command = plan

  variables {
    rules = [
      {
        rule_name                    = "daily"
        schedule                     = "cron(0 5 * * ? *)"
        schedule_expression_timezone = "Europe/Berlin"
        recovery_point_tags          = { Source = "terraform" }
        copy_actions = [
          {
            destination_vault_arn = "arn:aws:backup:eu-west-1:123456789012:backup-vault:dr-vault"
            cold_storage_after    = 30
            delete_after          = 120
          },
        ]
      },
    ]
  }

  assert {
    condition     = one(one(aws_backup_plan.this.rule).copy_action).destination_vault_arn == "arn:aws:backup:eu-west-1:123456789012:backup-vault:dr-vault"
    error_message = "destination_vault_arn should be passed through to copy_action."
  }

  assert {
    condition     = one(one(one(aws_backup_plan.this.rule).copy_action).lifecycle).delete_after == 120
    error_message = "Copy delete_after should be passed through to the copy_action lifecycle."
  }

  assert {
    condition     = one(one(one(aws_backup_plan.this.rule).copy_action).lifecycle).cold_storage_after == 30
    error_message = "Copy cold_storage_after should be passed through to the copy_action lifecycle."
  }

  assert {
    condition     = one(aws_backup_plan.this.rule).schedule_expression_timezone == "Europe/Berlin"
    error_message = "schedule_expression_timezone should be passed through."
  }

  assert {
    condition     = one(aws_backup_plan.this.rule).recovery_point_tags["Source"] == "terraform"
    error_message = "recovery_point_tags should be passed through."
  }
}

run "copy_action_without_retention_has_no_lifecycle" {
  command = plan

  variables {
    rules = [
      {
        rule_name = "daily"
        schedule  = "cron(0 5 * * ? *)"
        copy_actions = [
          { destination_vault_arn = "arn:aws:backup:eu-west-1:123456789012:backup-vault:dr-vault" },
        ]
      },
    ]
  }

  assert {
    condition     = length(one(one(aws_backup_plan.this.rule).copy_action).lifecycle) == 0
    error_message = "A copy action with no retention values should render no lifecycle block."
  }
}

run "continuous_backup_within_35_days_is_accepted" {
  command = plan

  variables {
    rules = [
      {
        rule_name                = "pitr"
        schedule                 = "cron(0 5 * * ? *)"
        enable_continuous_backup = true
        delete_after             = 35
      },
    ]
  }

  assert {
    condition     = one(aws_backup_plan.this.rule).enable_continuous_backup == true
    error_message = "enable_continuous_backup should be passed through."
  }
}

run "rejects_continuous_backup_over_35_days" {
  command = plan

  variables {
    rules = [
      {
        rule_name                = "pitr"
        schedule                 = "cron(0 5 * * ? *)"
        enable_continuous_backup = true
        delete_after             = 36
      },
    ]
  }

  expect_failures = [var.rules]
}

# delete_after defaults to 30, which is inside the 35 day continuous backup
# limit, so enabling continuous backup needs no other change to the rule.
run "continuous_backup_with_default_delete_after_is_accepted" {
  command = plan

  variables {
    rules = [
      {
        rule_name                = "pitr"
        schedule                 = "cron(0 5 * * ? *)"
        enable_continuous_backup = true
      },
    ]
  }

  assert {
    condition     = one(one(aws_backup_plan.this.rule).lifecycle).delete_after == 30
    error_message = "A continuous backup rule should keep the 30 day delete_after default."
  }
}

run "rejects_continuous_backup_with_cold_storage" {
  command = plan

  variables {
    rules = [
      {
        rule_name                = "pitr"
        schedule                 = "cron(0 5 * * ? *)"
        enable_continuous_backup = true
        cold_storage_after       = 1
        delete_after             = 35
      },
    ]
  }

  # Also trips the cold_storage_after + 90 check; both are reported on var.rules.
  expect_failures = [var.rules]
}

run "rejects_copy_action_with_non_vault_arn" {
  command = plan

  variables {
    rules = [
      {
        rule_name = "daily"
        schedule  = "cron(0 5 * * ? *)"
        copy_actions = [
          { destination_vault_arn = "dr-vault" },
        ]
      },
    ]
  }

  expect_failures = [var.rules]
}

run "rejects_copy_action_cold_storage_without_90_day_gap" {
  command = plan

  variables {
    rules = [
      {
        rule_name = "daily"
        schedule  = "cron(0 5 * * ? *)"
        copy_actions = [
          {
            destination_vault_arn = "arn:aws:backup:eu-west-1:123456789012:backup-vault:dr-vault"
            cold_storage_after    = 30
            delete_after          = 100
          },
        ]
      },
    ]
  }

  expect_failures = [var.rules]
}

run "rejects_copy_action_zero_delete_after" {
  command = plan

  variables {
    rules = [
      {
        rule_name = "daily"
        schedule  = "cron(0 5 * * ? *)"
        copy_actions = [
          {
            destination_vault_arn = "arn:aws:backup:eu-west-1:123456789012:backup-vault:dr-vault"
            delete_after          = 0
          },
        ]
      },
    ]
  }

  expect_failures = [var.rules]
}

run "rejects_timezone_with_spaces" {
  command = plan

  variables {
    rules = [
      {
        rule_name                    = "daily"
        schedule                     = "cron(0 5 * * ? *)"
        schedule_expression_timezone = "Central European Time"
      },
    ]
  }

  expect_failures = [var.rules]
}

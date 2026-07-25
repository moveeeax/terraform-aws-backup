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

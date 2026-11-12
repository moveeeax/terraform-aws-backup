resource "aws_backup_vault" "this" {
  name        = var.vault_name
  kms_key_arn = var.kms_key_arn

  tags = var.tags
}

resource "aws_backup_plan" "this" {
  name = var.plan_name

  dynamic "rule" {
    for_each = var.rules
    content {
      rule_name                    = rule.value.rule_name
      target_vault_name            = aws_backup_vault.this.name
      schedule                     = rule.value.schedule
      schedule_expression_timezone = rule.value.schedule_expression_timezone
      start_window                 = rule.value.start_window
      completion_window            = rule.value.completion_window
      enable_continuous_backup     = rule.value.enable_continuous_backup
      recovery_point_tags          = length(rule.value.recovery_point_tags) > 0 ? rule.value.recovery_point_tags : null

      lifecycle {
        cold_storage_after = rule.value.cold_storage_after
        delete_after       = rule.value.delete_after
      }

      dynamic "copy_action" {
        for_each = rule.value.copy_actions
        content {
          destination_vault_arn = copy_action.value.destination_vault_arn

          # Rendered only when the caller set at least one retention value, so
          # a copy action without retention settings sends no empty Lifecycle.
          dynamic "lifecycle" {
            for_each = copy_action.value.delete_after != null || copy_action.value.cold_storage_after != null ? [copy_action.value] : []
            content {
              cold_storage_after = lifecycle.value.cold_storage_after
              delete_after       = lifecycle.value.delete_after
            }
          }
        }
      }
    }
  }

  tags = var.tags
}

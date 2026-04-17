# harness_overrides.tf — Cross-org service overrides into business_unit_one / ecs_project.
#
# Confirmed: harness_platform_service_overrides_v2 attributes from Harness provider docs:
#   Required: env_id, type
#   Optional: org_id, project_id, service_id, identifier, yaml
# Confirmed: type = "ENV_SERVICE_OVERRIDE" for per-service environment overrides.
# Confirmed: yaml attribute takes the override spec body (variables/manifests/configFiles).

resource "harness_platform_service_overrides_v2" "service" {
  for_each = var.services

  org_id     = var.harness_app_org
  project_id = var.harness_app_project
  env_id     = var.harness_app_env_id
  service_id = each.key
  type       = "ENV_SERVICE_OVERRIDE"
  identifier = "${var.harness_app_env_id}_${each.key}"

  yaml = templatefile("${path.module}/templates/override.yaml.tftpl", {
    env_id             = var.harness_app_env_id
    service_id         = each.key
    is_blue_green      = local.is_blue_green
    blue_tg_arn        = aws_lb_target_group.blue[each.key].arn
    green_tg_arn       = local.is_blue_green ? aws_lb_target_group.green[each.key].arn : ""
    listener_arn       = aws_lb_listener.http.arn
    task_role_arn      = each.value.task_role_arn
    execution_role_arn = each.value.execution_role_arn
  })
}

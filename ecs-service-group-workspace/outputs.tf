# outputs.tf

output "alb_dns_name" {
  description = "DNS name of the shared ALB."
  value       = aws_lb.main.dns_name
}

output "alb_arn" {
  description = "ARN of the shared ALB."
  value       = aws_lb.main.arn
}

output "listener_arn" {
  description = "ARN of the HTTP listener."
  value       = aws_lb_listener.http.arn
}

output "services" {
  description = "Per-service resource map: blue_tg_arn, green_tg_arn (null if rolling), listener_rule_arn, override_id."
  value = {
    for key, svc in var.services : key => {
      blue_tg_arn       = aws_lb_target_group.blue[key].arn
      green_tg_arn      = local.is_blue_green ? aws_lb_target_group.green[key].arn : null
      listener_rule_arn = aws_lb_listener_rule.service[key].arn
      override_id       = harness_platform_service_overrides_v2.service[key].id
    }
  }
}

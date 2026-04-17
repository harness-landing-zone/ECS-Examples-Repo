resource "aws_lb_listener_rule" "service" {
  for_each = var.services

  listener_arn = aws_lb_listener.http.arn
  priority     = local.service_priorities[each.key]

  # Rolling: single forward to blue TG (weight 100 implied).
  # Blue/green: weighted forward — blue 100, green 0 (Harness shifts at runtime).
  action {
    type = "forward"

    forward {
      target_group {
        arn    = aws_lb_target_group.blue[each.key].arn
        weight = 100
      }

      dynamic "target_group" {
        for_each = local.is_blue_green ? [1] : []
        content {
          arn    = aws_lb_target_group.green[each.key].arn
          weight = 0
        }
      }
    }
  }

  condition {
    host_header {
      values = [each.value.host_header]
    }
  }

  # See CONSTRAINT comment above.
  lifecycle {
    ignore_changes = [action]
  }

  tags = {
    Name    = "${var.env}-${each.key}-rule"
    Service = each.key
  }
}

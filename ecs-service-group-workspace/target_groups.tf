# target_groups.tf

# Blue TG: always created for every service. # Confirmed: AWS docs — target_type "ip" for Fargate/awsvpc.
resource "aws_lb_target_group" "blue" {
  for_each = var.services

  name        = local.tg_names_blue[each.key]
  port        = each.value.container_port
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.selected.id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = each.value.health_check_path
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  tags = {
    Name    = local.tg_names_blue[each.key]
    Service = each.key
    Variant = "blue"
  }
}

# Green TG: only in blue_green strategy.
resource "aws_lb_target_group" "green" {
  for_each = local.is_blue_green ? var.services : {}

  name        = local.tg_names_green[each.key]
  port        = each.value.container_port
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.selected.id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = each.value.health_check_path
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  tags = {
    Name    = local.tg_names_green[each.key]
    Service = each.key
    Variant = "green"
  }
}

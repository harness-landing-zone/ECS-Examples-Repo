# security_groups.tf

# ALB security group: ingress 80 from anywhere, egress all.
resource "aws_security_group" "alb" {
  name        = "${var.env}-ecs-alb-sg"
  description = "Security group for the shared ECS ALB (${var.env})"
  vpc_id      = data.aws_vpc.selected.id

  tags = {
    Name = "${var.env}-ecs-alb-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from anywhere"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "alb_all" {
  security_group_id = aws_security_group.alb.id
  description       = "Allow all outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# ECS task security group: ingress on each service port from ALB SG only, egress all.
resource "aws_security_group" "ecs_tasks" {
  name        = "${var.env}-ecs-tasks-sg"
  description = "Security group for ECS tasks (${var.env})"
  vpc_id      = data.aws_vpc.selected.id

  tags = {
    Name = "${var.env}-ecs-tasks-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "ecs_from_alb" {
  for_each = var.services

  security_group_id            = aws_security_group.ecs_tasks.id
  description                  = "ALB to ${each.key} on port ${each.value.container_port}"
  from_port                    = each.value.container_port
  to_port                      = each.value.container_port
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.alb.id
}

resource "aws_vpc_security_group_egress_rule" "ecs_all" {
  security_group_id = aws_security_group.ecs_tasks.id
  description       = "Allow all outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

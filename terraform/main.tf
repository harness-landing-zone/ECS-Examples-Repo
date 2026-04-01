terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = "eu-west-2"
}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "ecs_task_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

variable "name" {
  description = "Name prefix for all resources"
  type        = string
}

variable "vpc_id" {
  description = "VPC where the ALB and target groups will be created"
  type        = string
}

variable "subnet_ids" {
  description = "At least 2 public subnets in different AZs for the ALB"
  type        = list(string)
}

variable "dev_subnet_1" {
  description = "Dev private/app subnet 1"
  type        = string
}

variable "dev_subnet_2" {
  description = "Dev private/app subnet 2"
  type        = string
}

variable "prod_subnet_1" {
  description = "Prod private/app subnet 1"
  type        = string
}

variable "prod_subnet_2" {
  description = "Prod private/app subnet 2"
  type        = string
}

variable "container_port" {
  description = "Application container port"
  type        = number
  default     = 8080
}

variable "health_check_path" {
  description = "HTTP health check path"
  type        = string
  default     = "/actuator/health"
}

variable "enable_https" {
  description = "Create HTTPS listener for production-style blue/green testing"
  type        = bool
  default     = false
}

variable "certificate_arn" {
  description = "ACM certificate ARN for HTTPS listener"
  type        = string
  default     = null
}

variable "tags" {
  type    = map(string)
  default = {}
}

locals {
  common_tags = merge(var.tags, {
    ManagedBy = "Terraform"
    Name      = var.name
  })
}

# ------------------------------------------------------------
# IAM ROLES
# ------------------------------------------------------------

resource "aws_iam_role" "ecs_task_execution" {
  name               = "${var.name}-ecs-task-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json

  tags = merge(local.common_tags, {
    Name = "${var.name}-ecs-task-execution-role"
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_managed" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "app1_task_role" {
  name               = "${var.name}-app1-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json

  tags = merge(local.common_tags, {
    Name = "${var.name}-app1-task-role"
  })
}

resource "aws_iam_role" "app2_task_role" {
  name               = "${var.name}-app2-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json

  tags = merge(local.common_tags, {
    Name = "${var.name}-app2-task-role"
  })
}

# ------------------------------------------------------------
# SECURITY GROUPS
# ------------------------------------------------------------

resource "aws_security_group" "alb" {
  name_prefix = "${var.name}-alb-"
  description = "ALB security group"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP inbound"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  dynamic "ingress" {
    for_each = var.enable_https ? [1] : []
    content {
      description = "HTTPS inbound"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  ingress {
    description = "Stage/Test listener inbound"
    from_port   = 9002
    to_port     = 9002
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.name}-alb-sg"
  })
}

resource "aws_security_group" "ecs_dev" {
  name_prefix = "${var.name}-ecs-dev-"
  description = "ECS service security group for Dev"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Allow ALB to reach dev ECS tasks"
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name        = "${var.name}-ecs-dev-sg"
    Environment = "dev"
  })
}

resource "aws_security_group" "ecs_prod" {
  name_prefix = "${var.name}-ecs-prod-"
  description = "ECS service security group for Prod"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Allow ALB to reach prod ECS tasks"
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name        = "${var.name}-ecs-prod-sg"
    Environment = "prod"
  })
}

# ------------------------------------------------------------
# ALB
# ------------------------------------------------------------

resource "aws_lb" "this" {
  name               = substr("${var.name}-alb", 0, 32)
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.subnet_ids

  enable_deletion_protection = false
  idle_timeout               = 60

  tags = merge(local.common_tags, {
    Name = "${var.name}-alb"
  })
}

# ------------------------------------------------------------
# TARGET GROUPS
# ------------------------------------------------------------

resource "aws_lb_target_group" "blue" {
  name        = substr("${var.name}-blue-tg", 0, 32)
  port        = var.container_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id

  deregistration_delay = 30

  health_check {
    enabled             = true
    path                = var.health_check_path
    port                = "traffic-port"
    protocol            = "HTTP"
    matcher             = "200-399"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = merge(local.common_tags, {
    Name = "${var.name}-blue-tg"
    Role = "blue"
  })
}

resource "aws_lb_target_group" "green" {
  name        = substr("${var.name}-green-tg", 0, 32)
  port        = var.container_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id

  deregistration_delay = 30

  health_check {
    enabled             = true
    path                = var.health_check_path
    port                = "traffic-port"
    protocol            = "HTTP"
    matcher             = "200-399"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = merge(local.common_tags, {
    Name = "${var.name}-green-tg"
    Role = "green"
  })
}

resource "aws_lb_target_group" "test" {
  name        = substr("${var.name}-test-tg", 0, 32)
  port        = var.container_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id

  deregistration_delay = 30

  health_check {
    enabled             = true
    path                = var.health_check_path
    port                = "traffic-port"
    protocol            = "HTTP"
    matcher             = "200-399"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = merge(local.common_tags, {
    Name = "${var.name}-test-tg"
    Role = "test"
  })
}

# ------------------------------------------------------------
# LISTENERS
# ------------------------------------------------------------

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.blue.arn
  }
}

resource "aws_lb_listener" "https" {
  count = var.enable_https ? 1 : 0

  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.blue.arn
  }
}

resource "aws_lb_listener" "test" {
  load_balancer_arn = aws_lb.this.arn
  port              = 9002
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.green.arn
  }
}

# ------------------------------------------------------------
# LISTENER RULES
# ------------------------------------------------------------

resource "aws_lb_listener_rule" "prod" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.blue.arn
  }

  condition {
    path_pattern {
      values = ["/*"]
    }
  }

  tags = merge(local.common_tags, {
    Name = "${var.name}-prod-rule"
    Role = "prod"
  })
}

resource "aws_lb_listener_rule" "stage" {
  listener_arn = aws_lb_listener.test.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.green.arn
  }

  condition {
    path_pattern {
      values = ["/*"]
    }
  }

  tags = merge(local.common_tags, {
    Name = "${var.name}-stage-rule"
    Role = "stage"
  })
}

# ------------------------------------------------------------
# OUTPUTS - ALB / BLUE-GREEN
# ------------------------------------------------------------

output "alb_arn" {
  value = aws_lb.this.arn
}

output "alb_name" {
  value = aws_lb.this.name
}

output "alb_dns_name" {
  value = aws_lb.this.dns_name
}

output "alb_zone_id" {
  value = aws_lb.this.zone_id
}

output "alb_security_group_id" {
  value = aws_security_group.alb.id
}

output "prod_listener_arn" {
  value = aws_lb_listener.http.arn
}

output "https_listener_arn" {
  value = var.enable_https ? aws_lb_listener.https[0].arn : null
}

output "stage_listener_arn" {
  value = aws_lb_listener.test.arn
}

output "prod_listener_rule_arn" {
  value = aws_lb_listener_rule.prod.arn
}

output "stage_listener_rule_arn" {
  value = aws_lb_listener_rule.stage.arn
}

output "blue_target_group_arn" {
  value = aws_lb_target_group.blue.arn
}

output "green_target_group_arn" {
  value = aws_lb_target_group.green.arn
}

output "test_target_group_arn" {
  value = aws_lb_target_group.test.arn
}

# ------------------------------------------------------------
# OUTPUTS - DEV OVERRIDES
# ------------------------------------------------------------

output "dev_subnet_1" {
  value = var.dev_subnet_1
}

output "dev_subnet_2" {
  value = var.dev_subnet_2
}

output "dev_security_group_id" {
  value = aws_security_group.ecs_dev.id
}

output "dev_assign_public_ip" {
  value = "DISABLED"
}

output "dev_execution_role_arn" {
  value = aws_iam_role.ecs_task_execution.arn
}

output "dev_task_role_app1_arn" {
  value = aws_iam_role.app1_task_role.arn
}

output "dev_task_role_app2_arn" {
  value = aws_iam_role.app2_task_role.arn
}

output "dev_ecr_registry_id" {
  value = data.aws_caller_identity.current.account_id
}

# ------------------------------------------------------------
# OUTPUTS - PROD OVERRIDES
# ------------------------------------------------------------

output "prod_subnet_1" {
  value = var.prod_subnet_1
}

output "prod_subnet_2" {
  value = var.prod_subnet_2
}

output "prod_security_group_id" {
  value = aws_security_group.ecs_prod.id
}

output "prod_assign_public_ip" {
  value = "DISABLED"
}

output "prod_execution_role_arn" {
  value = aws_iam_role.ecs_task_execution.arn
}

output "prod_task_role_app1_arn" {
  value = aws_iam_role.app1_task_role.arn
}

output "prod_task_role_app2_arn" {
  value = aws_iam_role.app2_task_role.arn
}

output "prod_ecr_registry_id" {
  value = data.aws_caller_identity.current.account_id
}
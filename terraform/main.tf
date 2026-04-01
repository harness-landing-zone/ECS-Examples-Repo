terraform {
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

variable "name" {
  description = "Name prefix for all resources"
  type        = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  description = "At least 2 subnets in different AZs"
  type        = list(string)
}

variable "container_port" {
  type    = number
  default = 8080
}

variable "health_check_path" {
  type    = string
  default = "/actuator/health"
}

variable "tags" {
  type    = map(string)
  default = {}
}

# --- Security Group ---

resource "aws_security_group" "alb" {
  name_prefix = "${var.name}-alb-"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name}-alb-sg" })
}

# --- ALB ---

resource "aws_lb" "this" {
  name               = "${var.name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.subnet_ids

  tags = merge(var.tags, { Name = "${var.name}-alb" })
}

resource "aws_lb_target_group" "blue" {
  name        = "${var.name}-tg-blue"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip" # Required for Fargate

  health_check {
    path     = var.health_check_path
    port     = "traffic-port"
    matcher  = "200"
    interval = 30
    timeout  = 5
  }

  tags = merge(var.tags, { Name = "${var.name}-tg" })
}

resource "aws_lb_target_group" "green" {
  name        = "${var.name}-tg-green"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip" # Required for Fargate

  health_check {
    path     = var.health_check_path
    port     = "traffic-port"
    matcher  = "200"
    interval = 30
    timeout  = 5
  }

  tags = merge(var.tags, { Name = "${var.name}-tg" })
}

# --- Listener ---

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}

output "alb_name" {
  value = aws_lb.this.name
}

output "alb_dns_name" {
  value = aws_lb.this.dns_name
}

output "target_group_arn" {
  value = aws_lb_target_group.this.arn
}

output "alb_security_group_id" {
  value = aws_security_group.alb.id
}

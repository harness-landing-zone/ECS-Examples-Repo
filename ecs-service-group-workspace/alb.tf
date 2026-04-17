
resource "aws_lb" "main" {
  name               = substr("${var.env}-ecs-svc-group", 0, 32)
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = data.aws_subnets.alb.ids

  tags = {
    Name = "${var.env}-ecs-svc-group"
  }
}

# HTTP listener on port 80 with fixed-response 404 default action.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Not Found"
      status_code  = "404"
    }
  }
}

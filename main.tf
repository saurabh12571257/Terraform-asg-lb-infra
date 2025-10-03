#------------------------------------
# Key Pair
#------------------------------------
resource "aws_key_pair" "ec2_key" {
  key_name   = "ec2_key"
  public_key = file(var.public_key_path)
}

#------------------------------------
# Use Default VPC (do NOT create it)
#------------------------------------
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
  filter {
    name   = "availability-zone"
    values = ["ap-south-1a", "ap-south-1b"]
  }
}

#------------------------------------
# Security Group for ALB (frontend)
#------------------------------------
resource "aws_security_group" "alb_sg" {
  name   = "alb-sg"
  vpc_id = data.aws_vpc.default.id

  description = "Allow HTTP/HTTPS from internet to ALB"

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "alb-sg" }
}

#------------------------------------
# Security Group for EC2 (backend)
#------------------------------------
resource "aws_security_group" "ec2_sg" {
  name   = "ec2-sg"
  vpc_id = data.aws_vpc.default.id

  description = "Allow traffic from ALB and SSH from admin IP"

  # Allow HTTP only from ALB security group
  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
    description     = "Allow ALB to reach instances on HTTP"
  }

  # Restrict SSH to your IP (replace with var.my_ip or set a CIDR variable)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
    description = "SSH from admin"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "ec2-sg" }
}

#------------------------------------
# Application Load Balancer
#------------------------------------
resource "aws_lb" "app_lb" {
  name               = "web-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = data.aws_subnets.default.ids

  enable_deletion_protection = false

  tags = { Name = "app-lb" }
}

#------------------------------------
# Target Group
#------------------------------------
resource "aws_lb_target_group" "tg" {
  name        = "web-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.default.id
  target_type = "instance"

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200-399"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = { Name = "web-tg" }
}

#------------------------------------
# Listener (HTTP -> TG)
#------------------------------------
resource "aws_lb_listener" "http_listener" {
  load_balancer_arn = aws_lb.app_lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

#------------------------------------
# Launch Template (recommended over Launch Configuration)
#------------------------------------
resource "aws_launch_template" "asg_lt" {
  name_prefix   = "web-asg-"

  image_id      = var.ami
  instance_type = var.instance_type

  key_name = aws_key_pair.ec2_key.key_name

  vpc_security_group_ids = [aws_security_group.ec2_sg.id]

  user_data = filebase64("user_data.sh")

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = 8
      volume_type           = "gp3"
      delete_on_termination = true
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

#------------------------------------
# Auto Scaling Group
#------------------------------------
resource "aws_autoscaling_group" "asg" {
  name                      = "web-asg"
  min_size                  = var.asg_min
  max_size                  = var.asg_max
  desired_capacity          = var.asg_desired
  vpc_zone_identifier       = data.aws_subnets.default.ids
  target_group_arns         = [aws_lb_target_group.tg.arn]

  launch_template {
    id      = aws_launch_template.asg_lt.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "web-asg-instance"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}
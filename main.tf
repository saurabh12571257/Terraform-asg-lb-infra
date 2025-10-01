resource aws_key_pair ec2_key {
    key_name   = "ec2_key"
    public_key = file(var.public_key_path)
}

resource aws_default_vpc default {
  tags = {
    Name = "Default VPC"
  }
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [aws_default_vpc.default.id]
  }
}

resource "aws_instance" "my_instance" {
  for_each = tomap({
    "first_instance" = "t2.micro"
    "second_instance" = "t3.micro"
  })

  ami           = var.ami
  instance_type = each.value
  security_groups = [aws_security_group.my_instance_sg.name]
  key_name      = aws_key_pair.ec2_key.key_name
  user_data = file("user_data.sh")

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
    delete_on_termination = true
  }



  tags = {
    Name = each.key
  }
}

resource "aws_security_group" "my_instance_sg" {
    name   = "my_instance_sg"
    vpc_id = aws_default_vpc.default.id

    ingress {
        from_port = 22
        to_port   = 22
        protocol  = "tcp"
        cidr_blocks = ["0.0.0.0/0"]

    }

    ingress {
        from_port       = 80
        to_port         = 80
        protocol        = "tcp"
        cidr_blocks    = ["0.0.0.0/0"] # ALB SG
    }

    egress {
        from_port = 0
        to_port   = 0
        protocol  = "-1"
        cidr_blocks = ["0.0.0.0/0"]
        description = "Allow all outbound traffic"
    }
}

#Target Group
resource "aws_lb_target_group" "tg" {
    name = "web-tg"
    port = 80
    protocol = "HTTP"
    vpc_id = aws_default_vpc.default.id
    target_type = "instance"

    health_check {
        path = "/"
        protocol = "HTTP"
        matcher = "200-399"
        interval = 30
        timeout = 5
        healthy_threshold = 2
        unhealthy_threshold = 2
    }
}

# Attach Ec2 instance to the Target Group
resource "aws_lb_target_group_attachment" "tg_attachment" {
    for_each = aws_instance.my_instance
    target_group_arn = aws_lb_target_group.tg.arn
    target_id = each.value.id
    port = 80
}

# Load Balancer
resource "aws_lb" "app_lb" {
    name = "web-lb"
    internal = false
    load_balancer_type = "application"
    security_groups = [aws_security_group.my_instance_sg.id]
    subnets = data.aws_subnets.default.ids

    enable_deletion_protection = false

    tags = {
        Name = "app-lb"
    }
}

# Listner for Load Balancer
resource "aws_lb_listener" "app_lb_listener" {
    load_balancer_arn = aws_lb.app_lb.arn
    port = 80
    protocol = "HTTP"

    default_action {
        type = "forward"
        target_group_arn = aws_lb_target_group.tg.arn
    }
}
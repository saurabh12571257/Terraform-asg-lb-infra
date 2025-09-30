resource aws_key_pair ec2_key {
    key_name   = "ec2_key"
    public_key = file(var.public_key_path)
}

resource aws_default_vpc default {
  tags = {
    Name = "Default VPC"
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

    egress {
        from_port = 0
        to_port   = 0
        protocol  = "-1"
        cidr_blocks = ["0.0.0.0/0"]
        description = "Allow all outbound traffic"
    }
}
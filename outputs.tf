output "ec2_publicip" {
    value = aws_instance.first_instance.public_ip
    description = "The public IP of the EC2 instance"
}
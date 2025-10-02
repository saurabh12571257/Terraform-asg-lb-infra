output "instance_public_ips" {
  value = [for instance in aws_instance.my_instance : instance.public_ip]
}

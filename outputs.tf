output "alb_dns_name" {
  value = aws_lb.app_lb.dns_name
}

output "target_group_arn" {
  value = aws_lb_target_group.tg.arn
}

output "ec2_instance_ip" {
    value = aws_launch_template.asg_lt.id
}
output "website_url" {
 description = "HTTP URL on the ALB."
 value = format("http://%s", aws_lb.web.dns_name)
}
output "alb_dns_name" {
 value = aws_lb.web.dns_name
}
output "task_security_group_id" {
 value = aws_security_group.task.id
}
output "alb_security_group_id" {
 value = aws_security_group.alb.id
}
output "public_subnet_ids" {
 value = aws_subnet.public[*].id
}

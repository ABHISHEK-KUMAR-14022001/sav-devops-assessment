variable "aws_region" {
 type = string
 default = "ap-south-1"
}
variable "name_prefix" {
 type = string
 default = "sav-web-assessment"
}
variable "container_image" {
 type = string
 default = "public.ecr.aws/docker/library/nginx:stable-alpine"
}

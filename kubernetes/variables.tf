variable "cluster_name" {
  description = "Name of the AWS Minikube cluster - will be used to name all created resources"
}

variable "tags" {
  description = "Tags used for the AWS resources created by this template"
  type        = "map"
}

variable "aws_instance_type" {
  description = "Type of instance"
  default     = "t2.medium"
}


variable "ssh_public_key" {
  description = "Path to the pulic part of SSH key which should be used for the instance"
  default     = "~/.ssh/id_rsa.pub"
}

variable "ami_image_id" {
  description = "ID of the AMI image which should be used. If empty, the latest CentOS 7 image will be used. See README.md for AMI image requirements."
  default = "ami-099b2d1bdd27b4649"
}

variable control_cidr {
  description = "CIDR for maintenance: inbound traffic will be allowed from this IPs"
}

variable vpc_name {
  description = "Name of the VPC"
  default = "kubernetes"
}

variable owner {
  default = "Kubernetes"
}

# Networking setup
variable region {
  default = "eu-west-1"
}

variable profile {
  default = "enekofb"
}

variable zone {
  default = "eu-west-1a"
}

variable vpc_cidr {
  default = "10.43.0.0/16"
}

variable kubernetes_pod_cidr {
  default = "10.200.0.0/16"
}
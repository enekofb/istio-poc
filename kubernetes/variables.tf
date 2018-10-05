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

variable "hosted_zone" {
  description = "Hosted zone to be used for the alias"
  default     = "enekofb.org"
}

variable "hosted_zone_private" {
  description = "Is the hosted zone public or private"
  default     = true
}

variable "ami_image_id" {
  description = "ID of the AMI image which should be used. If empty, the latest CentOS 7 image will be used. See README.md for AMI image requirements."
  default = "ami-099b2d1bdd27b4649"
}

# Tagging variables
variable "application" {
  description = "Application or Services are used by Tax to identify systems"
  type        = "string"
  default = "egress-minikubee"
}

variable "assetprotectionlevel" {
  description = "The security organization introduced the Crown Jewel concept to ensure we are focusing our efforts on the right applications, services, data, etc"
  type        = "string"
  default     = "6"
}

variable "brand" {
  description = "Organization below a line of business (LOB) providing engineering management, development, and support of primary services and applications"
  type        = "string"
  default     = "Hotels.com"
}

variable "costcenter" {
  description = "CostCenter tag (30119 - Thierry Bedos, 30166/30167 - Matt Fryer)"
  type        = "string"
  default     = "30119"
}

variable "dataclassification" {
  description = "DataClassification tag (HighlySensitive, Sensitive, Confidential, Public)"
  type        = "string"
  default     = "Public"
}

variable "environment" {
  description = "Environment tag (Secure, Prod, Corp, Lab, DataWarehouse)"
  type        = "string"
  default     = "Lab"
}

variable "launchedby" {
  description = "LaunchedBy tag (e.g. terraform-api)"
  type        = "string"
  default     = "terraform-api"
}

variable "team" {
  description = "Team tag (HCOM_...)"
  type        = "string"
  default     = "HCOM_PAWS"
}


variable control_cidr {
  description = "CIDR for maintenance: inbound traffic will be allowed from this IPs"
}

variable default_keypair_name {
  description = "Name of the KeyPair used for all nodes"
  default = "k8s-not-the-hardest-way"
}


variable vpc_name {
  description = "Name of the VPC"
  default = "kubernetes"
}

variable elb_name {
  description = "Name of the ELB for Kubernetes API"
  default = "kubernetes"
}

variable owner {
  default = "Kubernetes"
}

variable ansibleFilter {
  description = "`ansibleFilter` tag value added to all instances, to enable instance filtering in Ansible dynamic inventory"
  default = "Kubernetes01" # IF YOU CHANGE THIS YOU HAVE TO CHANGE instance_filters = tag:ansibleFilter=Kubernetes01 in ./ansible/hosts/ec2.ini
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

### VARIABLES BELOW MUST NOT BE CHANGED ###

variable vpc_cidr {
  default = "10.43.0.0/16"
}

variable kubernetes_pod_cidr {
  default = "10.200.0.0/16"
}


variable default_instance_user {
  default = "ubuntu"
}

variable etcd_instance_type {
  default = "t2.small"
}
variable controller_instance_type {
  default = "t2.small"
}
variable worker_instance_type {
  default = "t2.small"
}


variable kubernetes_cluster_dns {
  default = "10.31.0.1"
}

provider "aws" {
  region = "${var.region}"
  profile = "${var.profile}"
}

############
## VPC
############

resource "aws_vpc" "kubernetes" {
  cidr_block = "${var.vpc_cidr}"
  enable_dns_hostnames = true

  tags {
    Name = "${var.vpc_name}"
    Owner = "${var.owner}"
  }
}

# DHCP Options are not actually required, being identical to the Default Option Set
resource "aws_vpc_dhcp_options" "dns_resolver" {
  domain_name = "${var.region}.compute.internal"
  domain_name_servers = ["AmazonProvidedDNS"]

  tags {
    Name = "${var.vpc_name}"
    Owner = "${var.owner}"
  }
}

resource "aws_vpc_dhcp_options_association" "dns_resolver" {
  vpc_id ="${aws_vpc.kubernetes.id}"
  dhcp_options_id = "${aws_vpc_dhcp_options.dns_resolver.id}"
}

############
## Subnets
############

# Subnet (public)
resource "aws_subnet" "kubernetes" {
  vpc_id = "${aws_vpc.kubernetes.id}"
  cidr_block = "${var.vpc_cidr}"
  availability_zone = "${var.zone}"

  tags {
    Name = "kubernetes"
    Owner = "${var.owner}"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = "${aws_vpc.kubernetes.id}"
  tags {
    Name = "kubernetes"
    Owner = "${var.owner}"
  }
}

############
## Routing
############

resource "aws_route_table" "kubernetes" {
  vpc_id = "${aws_vpc.kubernetes.id}"

  # Default route through Internet Gateway
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.gw.id}"
  }

  tags {
    Name = "kubernetes"
    Owner = "${var.owner}"
  }
}

resource "aws_route_table_association" "kubernetes" {
  subnet_id = "${aws_subnet.kubernetes.id}"
  route_table_id = "${aws_route_table.kubernetes.id}"
}


############
## Security
############

resource "aws_security_group" "kubernetes" {
  vpc_id = "${aws_vpc.kubernetes.id}"
  name = "kubernetes"

  # Allow all outbound
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow ICMP from control host IP
  ingress {
    from_port = 8
    to_port = 0
    protocol = "icmp"
    cidr_blocks = ["${var.control_cidr}"]
  }

  # Allow all internal
  ingress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["${var.vpc_cidr}"]
  }

  # Allow all traffic from the API ELB
  ingress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all traffic from control host IP
  ingress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["${var.control_cidr}"]
  }

  tags {
    Owner = "${var.owner}"
    Name = "kubernetes"
  }
}




#####
# IAM role
#####

data "template_file" "policy-json" {
  template = "${file("template/policy.json.tpl")}"

  vars {}
}

resource "aws_iam_policy" "host-egress-policy" {
  name        = "${var.cluster_name}"
  path        = "/"
  description = "Policy for role ${var.cluster_name}"
  policy      = "${data.template_file.policy-json.rendered}"
}

resource "aws_iam_role" "host-egress-role" {
  name = "${var.cluster_name}"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_policy_attachment" "host-egress-attach" {
  name       = "host-egress-attachment"
  roles      = ["${aws_iam_role.host-egress-role.name}"]
  policy_arn = "${aws_iam_policy.host-egress-policy.arn}"
}

resource "aws_iam_instance_profile" "host-egress-profile" {
  name = "${var.cluster_name}"
  role = "${aws_iam_role.host-egress-role.name}"
}


##########
# Keypair
##########

resource "aws_key_pair" "host-egress-keypair" {
  key_name   = "${var.cluster_name}"
  public_key = "${file(var.ssh_public_key)}"
}

#####
# EC2 instance
#####

resource "aws_eip" "host-egress" {
  vpc = true
}

resource "aws_instance" "host-egress" {
  # Instance type - any of the c4 should do for now
  instance_type = "${var.aws_instance_type}"

  ami = "${var.ami_image_id}"

  key_name = "${aws_key_pair.host-egress-keypair.key_name}"

  subnet_id = "${aws_subnet.kubernetes.id}"

  associate_public_ip_address = true

  vpc_security_group_ids = [
    "${aws_security_group.kubernetes.id}",
  ]

  iam_instance_profile = "${aws_iam_instance_profile.host-egress-profile.name}"

  tags = "${merge(map("Name", var.cluster_name, format("kubernetes.io/cluster/%v", var.cluster_name), "owned"), var.tags)}"

  root_block_device {
    volume_type           = "gp2"
    volume_size           = "50"
    delete_on_termination = true
  }

  lifecycle {
    ignore_changes = [
      "ami",
      "user_data",
      "associate_public_ip_address",
    ]
  }
}

resource "aws_eip_association" "host-egress-assoc" {
  instance_id   = "${aws_instance.host-egress.id}"
  allocation_id = "${aws_eip.host-egress.id}"
}

//#####
//# DNS record
//#####
//
//data "aws_route53_zone" "dns-zone" {
//  name         = "${var.hosted_zone}."
//  private_zone = "${var.hosted_zone_private}"
//}
//
//resource "aws_route53_record" "host-egress" {
//  zone_id = "${data.aws_route53_zone.dns-zone.zone_id}"
//  name    = "${var.cluster_name}.${var.hosted_zone}"
//  type    = "A"
//  records = ["${aws_eip.host-egress.public_ip}"]
//  ttl     = 300
//}

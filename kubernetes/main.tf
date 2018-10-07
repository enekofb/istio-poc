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

resource "aws_internet_gateway" "igw" {
  vpc_id = "${aws_vpc.kubernetes.id}"
  tags {
    Name = "Internet Gateway"
    Owner = "${var.owner}"
  }
}

resource "aws_eip" "ngw-eip" {
  vpc      = true

}


resource "aws_nat_gateway" "ngw" {
  allocation_id = "${aws_eip.ngw-eip.id}"
  subnet_id     = "${aws_subnet.public.0.id}"

  tags {
    Name = "Nat Gateway"
    Owner = "${var.owner}"
  }

}

############
## Subnets
############

resource "aws_subnet" "public" {
  count = "${var.azs-count}"
  vpc_id = "${aws_vpc.kubernetes.id}"
  cidr_block = "${element(var.public-subnet-cidrs, count.index)}"
  availability_zone = "${element(var.azs, count.index)}"


  tags  {
    Name = "kubernetes-public"
    Owner = "${var.owner}"
  }
}

resource "aws_subnet" "private" {
  count = "${var.azs-count}"
  vpc_id = "${aws_vpc.kubernetes.id}"
  cidr_block = "${element(var.private-subnet-cidrs, count.index)}"
  availability_zone = "${element(var.azs, count.index)}"


  tags  {
    Name = "kubernetes-private"
    Owner = "${var.owner}"
  }
}


############
## Routing
############


resource "aws_route_table" "public" {
  vpc_id = "${aws_vpc.kubernetes.id}"

  # Default route through Internet Gateway
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.igw.id}"
  }

  tags {
    Name = "kubernetes"
    Owner = "${var.owner}"
  }
}

data "aws_subnet_ids" "private" {
  vpc_id = "${aws_vpc.kubernetes.id}"
  tags {
    Name = "kubernetes-private"
  }
}

data "aws_subnet_ids" "public" {
  vpc_id = "${aws_vpc.kubernetes.id}"
  tags {
    Name = "kubernetes-public"
  }
}

resource "aws_route_table_association" "public" {
  count = "${var.azs-count}"

  subnet_id = "${element(data.aws_subnet_ids.public.ids, count.index)}"
  route_table_id = "${aws_route_table.public.id}"
}


resource "aws_route_table" "private" {
  vpc_id = "${aws_vpc.kubernetes.id}"

  # Default route through Nat Gateway
  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = "${aws_nat_gateway.ngw.id}"
  }

  tags {
    Name = "kubernetes"
    Owner = "${var.owner}"
  }
}

resource "aws_route_table_association" "private" {
  count = "${var.azs-count}"

  subnet_id = "${element(data.aws_subnet_ids.private.ids, count.index)}"
  route_table_id = "${aws_route_table.private.id}"
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
  instance_type = "${var.aws_instance_type}"

  ami = "${var.ami_image_id}"

  key_name = "${aws_key_pair.host-egress-keypair.key_name}"

  subnet_id = "${aws_subnet.public.0.id}"

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

resource "aws_route53_zone" "external" {
  name = "${var.dns_name}"
}

//resource "aws_route53_record" "pegress" {
//  name    = "pegress.${var.dns_name}"
//  type    = "CNAME"
//  zone_id = "${aws_route53_zone.external.zone_id}"
//  ttl     = "60"
//}
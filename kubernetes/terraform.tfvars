# Name for role, policy and cloud formation stack (without DBG-DEV- prefix)
cluster_name = "egress"

# Tags
tags = {
  "Application" = "egress"
  "Environment"          = "test"
  "LaunchedBy"           = "terraform"
}

control_cidr= "165.225.81.22/32"
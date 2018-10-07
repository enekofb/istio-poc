# Name for role, policy and cloud formation stack (without DBG-DEV- prefix)
vpc_name = "kubernetes-prod"
# Tags
tags = {
  "Application" = "egress"
  "Environment"          = "prod"
  "LaunchedBy"           = "terraform"
}

dns_name = "prod.enekofb.org"

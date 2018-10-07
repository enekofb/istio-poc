//State with workspaces!!! notice that we are using workspaces (dev and prod)
terraform {
  backend "s3" {
    key     = "egress"
    bucket  = "7771-7135-9344-terraform-state"
    encrypt = "true"
    profile = "enekofb"
    region  = "eu-west-1"
  }
}

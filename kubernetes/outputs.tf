#####
# Output
#####

output "ssh_user" {
    description = "SSH user to download kubeconfig file"
    value = "core"
}

output "public_ip" {
    description = "Public IP address"
    value = "${aws_eip.host-egress.public_ip}"
}

//output "dns" {
//    description = "Minikube DNS address"
//    value = "${aws_route53_record.host-egress.fqdn}"
//}
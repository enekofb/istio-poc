#########################
## Generate certificates
#########################

# Generate Certificates
data "template_file" "certificates" {
    template = "${file("${path.module}/template/kubernetes-csr.json")}"
    vars {
      pegress_ip = "${aws_instance.host-egress.private_ip}"
      pegress_ip = "${aws_instance.host-egress.private_dns}"
    }
}
resource "null_resource" "certificates" {
  triggers {
    template_rendered = "${ data.template_file.certificates.rendered }"
  }
  provisioner "local-exec" {
    command = "echo '${ data.template_file.certificates.rendered }' > cert/kubernetes-csr.json"
  }
  provisioner "local-exec" {
    command = "cd cert; cfssl gencert -initca ca-csr.json | cfssljson -bare ca; cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes kubernetes-csr.json | cfssljson -bare kubernetes"
  }
}
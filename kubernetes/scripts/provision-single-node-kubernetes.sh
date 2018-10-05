#!/usr/bin/env bash

systemctl enable docker
systemctl start docker

export CNI_VERSION="v0.6.0"
mkdir -p /opt/cni/bin
curl -L "https://github.com/containernetworking/plugins/releases/download/$CNI_VERSION/cni-plugins-amd64-$CNI_VERSION.tgz" | tar -C /opt/cni/bin -xz

export RELEASE="$(curl -sSL https://dl.k8s.io/release/stable.txt)"

mkdir -p /opt/bin
cd /opt/bin
curl -L --remote-name-all https://storage.googleapis.com/kubernetes-release/release/$RELEASE/bin/linux/amd64/{kubeadm,kubelet,kubectl}
chmod +x {kubeadm,kubelet,kubectl}

curl -sSL "https://raw.githubusercontent.com/kubernetes/kubernetes/$RELEASE/build/debs/kubelet.service" | sed "s:/usr/bin:/opt/bin:g" > /etc/systemd/system/kubelet.service
mkdir -p /etc/systemd/system/kubelet.service.d
curl -sSL "https://raw.githubusercontent.com/kubernetes/kubernetes/$RELEASE/build/debs/10-kubeadm.conf" | sed "s:/usr/bin:/opt/bin:g" > /etc/systemd/system/kubelet.service.d/10-kubeadm.conf

systemctl enable kubelet && systemctl start kubelet

/opt/bin/kubeadm init --config=/home/core/kubeadm-config.yaml  kubeadm-config.yaml  --ignore-preflight-errors=all

export KUBECONFIG=/etc/kubernetes/admin.conf

cat <<EOF | kubectl apply -f -
apiVersion: policy/v1beta1
kind: PodSecurityPolicy
metadata:
  name: privileged
  annotations:
    seccomp.security.alpha.kubernetes.io/allowedProfileNames: '*'
spec:
  privileged: true
  allowPrivilegeEscalation: true
  allowedCapabilities:
  - '*'
  volumes:
  - '*'
  hostNetwork: true
  hostPorts:
  - min: 0
    max: 65535
  hostIPC: true
  hostPID: true
  runAsUser:
    rule: 'RunAsAny'
  seLinux:
    rule: 'RunAsAny'
  supplementalGroups:
    rule: 'RunAsAny'
  fsGroup:
    rule: 'RunAsAny'
EOF

cat <<EOF | kubectl apply -f -
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: psp-privileged-cr
rules:
- apiGroups: ['policy']
  resources: ['podsecuritypolicies']
  verbs:     ['use']
  resourceNames:
  - privileged
EOF


cat <<EOF | kubectl apply -n kube-system -f  -
kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: psp-privileged-rb
roleRef:
  kind: ClusterRole
  name: psp-privileged-cr
  apiGroup: rbac.authorization.k8s.io
subjects:
# Authorize all service accounts in a namespace:
- kind: Group
  apiGroup: rbac.authorization.k8s.io
  name: system:serviceaccounts
- kind: Group
  apiGroup: rbac.authorization.k8s.io
  name: system:nodes
EOF

kubectl apply -f https://docs.projectcalico.org/v3.1/getting-started/kubernetes/installation/hosted/kubeadm/1.7/calico.yaml

/opt/bin/kubectl taint nodes --all node-role.kubernetes.io/master-

mkdir -p /home/core/.kube && cp -f /etc/kubernetes/admin.conf /home/core/.kube/config && chown -R $(id -u core):$(id -g core) /home/core/

#selinux admin
cp --remove-destination $(readlink -f /etc/selinux/config) /etc/selinux/config

cat <<EOF > /etc/selinux/config
# This file controls the state of SELinux on the system on boot.

# SELINUX can take one of these three values:
#	enforcing - SELinux security policy is enforced.
#	enforcing - SELinux prints warnings instead of enforcing.
#	disabled - No SELinux policy is loaded.
SELINUX=enforcing

# SELINUXTYPE can take one of these four values:
#	targeted - Only targeted network daemons are protected.
#	strict   - Full SELinux protection.
#	mls      - Full SELinux protection with Multi-Level Security
#	mcs      - Full SELinux protection with Multi-Category Security
#	           (mls, but only one sensitivity level)
SELINUXTYPE=mcs
EOF

#Eneko
echo 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDP6bPuPHqP5aeKljKzlkrVQNYN4jbMei03IzhBVLkQYr1MGCvr0W28186U+eIgqDeNJcDCz7/nQvolBkMZkpzfNFGDQ0hhaT/9VE+EaVz3c9/ndT1EsLaGl4zotMZYXvsVBTmPtZQuKAQ1TJX/Be6tDj1lhxk7cu5S1a/URDYLBuVdhk8hyV3uHx+tVfGFqM/3n8AB+0VLHGcbi0fcnsE7mE82lQE6anG7PboPYgU3zvMMKw97gdiQ9/Ytfdc/wbrtLiEobkOuuziIUEnilZwd6qNmPspibdQyIsYtgfmWskipQDfPyOxt5cs2U4hEkYhsIJ1qwXqxnodUy7XNnAn69/MOQvTCakBPdNN+TQHjJ+fJRH/WbRksI6xe6+Xex0nlLPuFqg+f1PoEBQSHg1dUHNELXkKLjCFVs05TIDW0RzkvtA0in4RN1/UkZNIWOmOUerGFs2wgP0H6Ixgghg5Eq17ZNy6o8hSt5NOZQ4JPmvtOqWYPlSqHjPFtBaO1wDl9BIoHkqgU1bhnbRRlEKsV1EY6F2vFz8XbyVCHXRQqrLdtT1yuE4lqyk8y5lv4OxG9OZF+jXW9/jkNeh7T0TbCqGnTY8azXpgQktpOnbYVpF5fE1mZh2J2VxF+h14LP+MnrWee9PCREDDiOq8PAKn0TzOxeGy9VrnmAAqdLnGb0w== efernandezbrei@LONC02TNDMNG8WN.sea.corp.expecn.com' | update-ssh-keys -a eneko

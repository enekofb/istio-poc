#!/usr/bin/env bash

export HOME=/home/core
export KUBECONFIG=/etc/kubernetes/admin.conf
export ISTIO_VERSION=1.0.0

echo 'download helm'
curl https://raw.githubusercontent.com/kubernetes/helm/master/scripts/get > get_helm.sh
chmod 700 get_helm.sh
HELM_INSTALL_DIR=/opt/bin ./get_helm.sh

echo 'install istio'

curl -L https://github.com/istio/istio/releases/download/$ISTIO_VERSION/istio-$ISTIO_VERSION-linux.tar.gz |  tar xz

sudo mv istio-$ISTIO_VERSION/bin/istioctl /opt/bin/

kubectl apply -f istio-$ISTIO_VERSION/install/kubernetes/helm/helm-service-account.yaml

helm init --service-account tiller --wait

cat <<EOF | kubectl apply -f  -

apiVersion: v1
kind: Namespace
metadata:
  name: istio-system
spec:
  finalizers:
  - kubernetes
EOF

cat <<EOF | kubectl apply -n istio-system -f  -

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
EOF

helm install istio-$ISTIO_VERSION/install/kubernetes/helm/istio --name istio --namespace istio-system
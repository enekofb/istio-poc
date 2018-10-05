#!/usr/bin/env bash

kubectl auth can-i get pods -n kube-system|grep no
echo 'Cannot access to kube-system'

kubectl auth can-i get pods -n istio-system |grep no
echo 'Cannot access to istio-system'

#seccomp test
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: seccomp-test
spec:
      containers:
      - name: test
        image: "debian"
        command: ["/bin/bash", "-c", "apt update && apt -y install keyutils && keyctl show && sleep 3600"]
EOF

sleep 60

kubectl describe pods seccomp-test|grep kubernetes.io/psp=restricted-custom
echo 'PSP enabled'

kubectl logs seccomp-test|grep 'Unable to dump key: Operation not permitted'
echo 'SECCOMP working'

kubectl delete pod seccomp-test

export POD=$(kubectl get pod -l app=pegress-alpine-istio -o jsonpath="{.items[0].metadata.name}")
kubectl exec -ti $POD -- wget -O - www.google.com |grep Lucky
if [ $? -eq 0 ]; then
    echo 'Egreess worked'
else
    echo 'Egreess failed'
fi

kubectl exec -ti $POD -- wget -O - http://34.222.7.95 --header 'Host: www.google.com' |grep Lucky
if [ $? -eq 0 ]; then
    echo 'Egreess not bypassed'
else
    echo 'Egreess bypassed'
fi
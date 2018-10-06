#!/usr/bin/env bash

export HOME=/home/core
export KUBECONFIG=$HOME/.kube/config

cat <<EOF | kubectl apply -f -
apiVersion: policy/v1beta1
kind: PodSecurityPolicy
metadata:
  name: restricted-custom
  annotations:
    seccomp.security.alpha.kubernetes.io/allowedProfileNames: 'docker/default'
    seccomp.security.alpha.kubernetes.io/defaultProfileName:  'docker/default'
spec:
  privileged: false
  # Required to prevent escalations to root.
  allowPrivilegeEscalation: false
  allowedCapabilities:
  - NET_ADMIN
  # Allow core volume types.
  volumes:
    - 'configMap'
    - 'emptyDir'
    - 'projected'
    - 'secret'
    - 'downwardAPI'
    # Assume that persistentVolumes set up by the cluster admin are safe to use.
    - 'persistentVolumeClaim'
  hostNetwork: false
  hostIPC: false
  hostPID: false
  runAsUser:
    # Require the container to run without root privileges.
    rule: 'RunAsAny' ##  TODO: REMOVE ME NOTE THAT THIS IS BEACAUSE OF ISTIO PROXY
  seLinux:
    # This policy assumes the nodes are using AppArmor rather than SELinux.
    rule: 'RunAsAny'
  supplementalGroups:
    rule: 'MustRunAs'
    ranges:
      # Forbid adding the root group.
      - min: 1
        max: 65535
  fsGroup:
    rule: 'MustRunAs'
    ranges:
      # Forbid adding the root group.
      - min: 1
        max: 65535
  readOnlyRootFilesystem: false
EOF

cat <<EOF | kubectl apply -f -
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: psp-restricted-custom-cr
rules:
- apiGroups: ['policy']
  resources: ['podsecuritypolicies']
  verbs:     ['use']
  resourceNames:
  - restricted-custom
EOF


cat <<EOF | kubectl apply -n default -f  -

kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: psp-restricted-rb
roleRef:
  kind: ClusterRole
  name: psp-restricted-custom-cr
  apiGroup: rbac.authorization.k8s.io
subjects:
# Authorize all service accounts in a namespace:
- kind: Group
  apiGroup: rbac.authorization.k8s.io
  name: system:serviceaccounts
EOF


#create non admin user
cat <<EOF | kubectl apply -f  -
kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: pegress-default-admin
roleRef:
  kind: ClusterRole
  name: admin
  apiGroup: rbac.authorization.k8s.io
subjects:
# Authorize all service accounts in a namespace:
- kind: User
  apiGroup: rbac.authorization.k8s.io
  name: pegress
EOF


cat <<EOF | istioctl create -f -
apiVersion: networking.istio.io/v1alpha3
kind: ServiceEntry
metadata:
  name: google-ext
spec:
  hosts:
  - www.google.com
  resolution: DNS
  location: MESH_EXTERNAL
  ports:
  - number: 80
    name: http
    protocol: HTTP
  - number: 443
    name: https-port
    protocol: HTTPS
  endpoints:
  - address: www.google.com
EOF


cat <<EOF | kubectl apply -n default -f  -
apiVersion: v1
kind: Service
metadata:
  name: pegress-alpine-istio
  labels:
    app: pegress-alpine-istio
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-backend-protocol: http
    service.beta.kubernetes.io/aws-load-balancer-ssl-cert: 	arn:aws:acm:eu-west-1:777171359344:certificate/e53693cd-1b67-4eea-a581-76b2ac7146da
    service.beta.kubernetes.io/aws-load-balancer-ssl-ports: "https"
spec:
  ports:
  - port: 80
    targetPort: 8080
    name: http
  selector:
    app: pegress-alpine-istio
  type: LoadBalancer
---
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: pegress-alpine-istio
spec:
  replicas: 1
  strategy: {}
  template:
    metadata:
      labels:
        app: pegress-alpine-istio
    spec:
      containers:
      - image: enekofb/pegress-alpine
        name: pegress
        securityContext:
          privileged: false
          runAsNonRoot: true
          runAsUser: 1000
      - args:
        - proxy
        - sidecar
        - --configPath
        - /etc/istio/proxy
        - --binaryPath
        - /usr/local/bin/envoy
        - --serviceCluster
        - pegress-alpine-istio
        - --drainDuration
        - 45s
        - --parentShutdownDuration
        - 1m0s
        - --discoveryAddress
        - istio-pilot.istio-system:15007
        - --discoveryRefreshDelay
        - 1s
        - --zipkinAddress
        - zipkin.istio-system:9411
        - --connectTimeout
        - 10s
        - --statsdUdpAddress
        - istio-statsd-prom-bridge.istio-system:9125
        - --proxyAdminPort
        - "15000"
        - --controlPlaneAuthPolicy
        - NONE
        env:
        - name: POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: POD_NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        - name: INSTANCE_IP
          valueFrom:
            fieldRef:
              fieldPath: status.podIP
        - name: ISTIO_META_POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: ISTIO_META_INTERCEPTION_MODE
          value: REDIRECT
        image: docker.io/istio/proxyv2:1.0.0
        imagePullPolicy: IfNotPresent
        name: istio-proxy
        resources:
          requests:
            cpu: 10m
        securityContext:
          privileged: false
          readOnlyRootFilesystem: true
          runAsUser: 1337
        volumeMounts:
        - mountPath: /etc/istio/proxy
          name: istio-envoy
        - mountPath: /etc/certs/
          name: istio-certs
          readOnly: true
      initContainers:
      - args:
        - -p
        - "15001"
        - -u
        - "1337"
        - -m
        - REDIRECT
        - -i
        - '*'
        - -x
        - ""
        - -b
        - ""
        - -d
        - ""
        image: docker.io/istio/proxy_init:1.0.0
        imagePullPolicy: IfNotPresent
        name: istio-init
        resources: {}
        securityContext:
          capabilities:
            add:
            - NET_ADMIN
          privileged: false
      volumes:
      - emptyDir:
          medium: Memory
        name: istio-envoy
      - name: istio-certs
        secret:
          optional: true
          secretName: istio.default
EOF

cat <<EOF | kubectl apply -f  -
apiVersion: autoscaling/v1
kind: HorizontalPodAutoscaler
metadata:
  name: pegress-alpine-istio
  namespace: default
spec:
  maxReplicas: 5
  minReplicas: 1
  scaleTargetRef:
    apiVersion: extensions/v1beta1
    kind: Deployment
    name: pegress-alpine-istio
  targetCPUUtilizationPercentage: 75
EOF

#https://github.com/kubernetes/kubernetes/issues/64479
mkdir -p /home/core/.certs

openssl genrsa -out /home/core/.certs/pegress.key 2048
openssl req -new -key /home/core/.certs/pegress.key -out /home/core/.certs/pegress.csr -subj "/CN=pegress/O=hcom"
openssl x509 -req -in /home/core/.certs/pegress.csr -CA /etc/kubernetes/pki/ca.crt -CAkey /etc/kubernetes/pki/ca.key -CAcreateserial -out /home/core/.certs/pegress.crt -days 500

chown -R $(id -u core):$(id -g core) /home/core/.certs
chown -R $(id -u core):$(id -g core) /home/core/.kube/

kubectl config set-credentials pegress --client-certificate=/home/core/.certs/pegress.crt  --client-key=/home/core/.certs/pegress.key
kubectl config set-context pegress-context --cluster=kubernetes --namespace=default --user=pegress


kubectl config use-context pegress-context

kubectl config delete-context kubernetes-admin@kubernetes



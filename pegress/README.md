# PAWS Egress service

- Web server that listen for request at "/" it returns www.google.com landing page.

- The service listens in port 8080 (container not runing as root)
- Two versions of the containarised service

1. Scratch as parent image -> dropped interactive shell.
2. Alpine as parent image -> with interactive shell.

- kubernetes resources created:

1. Without [istio](pegress.yaml)
2. With [istio](pegress-istio.yaml)

- Test the service

```
curl -vk http://{POD_iP}:8080/

curl -vk http://{SERVICE_IP}:80/
```

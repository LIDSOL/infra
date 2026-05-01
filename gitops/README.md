Services exposure — IP vs Domain
================================

This document explains how to add new services in this repo and expose them either with a
MetalLB-assigned IP (internal/admin UIs) or with a public domain using Traefik + Ingress
and cert-manager for TLS.

Principles
----------
- Internal (IP): Use a `Service` of type `LoadBalancer` and set `loadBalancerIP` to an
	available address from the MetalLB pool. These services are intended for internal/admin
	access and do not require Ingress routing.
- External (Domain): Use a `ClusterIP` `Service` + a `Ingress` resource with
	`ingressClassName: traefik`. Traefik is the public entrypoint; certificates are handled
	with the `ClusterIssuer` named `https-issuer` (ACME HTTP-01).

MetalLB (IP-only) example
-------------------------
Create a LoadBalancer service and pin an IP from the MetalLB pool:

```yaml
apiVersion: v1
kind: Service
metadata:
	name: my-app-lb
	namespace: gitops
	labels:
		app: my-app
spec:
	type: LoadBalancer
	loadBalancerIP: 10.8.24.110   # pick an unused IP from the MetalLB pool
	selector:
		app: my-app
	ports:
		- name: http
			port: 80
			targetPort: 8080
```

Notes:
- Ensure the chosen `loadBalancerIP` is inside the `metallb` IP pool and not already used
	by another service (use `kubectl get svc -A -o wide` to check).
- Commit this manifest to the `gitops/` directory so ArgoCD will apply it.

Traefik + Ingress (domain) example
----------------------------------
Expose a service via Traefik using an Ingress. Replace hostnames with your domain.

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
	name: my-app-ingress
	namespace: gitops
	annotations:
		cert-manager.io/cluster-issuer: "https-issuer"
spec:
	ingressClassName: traefik
	tls:
		- hosts:
				- app.example.com
			secretName: https-my-app-tls
	rules:
		- host: app.example.com
			http:
				paths:
					- path: /
						pathType: Prefix
						backend:
							service:
								name: my-app
								port:
									number: 8080
```

Notes:
- `ingressClassName` must be `traefik` to match the cluster ingress controller.
- The `cert-manager` `ClusterIssuer` `https-issuer` will request TLS certs via HTTP-01.
- DNS A record for the domain must point to the public NAT IP that forwards to Traefik's
	MetalLB VIP (e.g. `132.248.59.72` NAT -> `10.8.24.103`).

Cert-manager & ACME notes
-------------------------
- We use the `ClusterIssuer` named `https-issuer` configured for HTTP-01 with solver
	targeting `traefik`. Do not change the solver class unless you change the controller.
- If a certificate stays `Pending` with `wrong status code '404'`, verify:
	1. DNS resolves to the public NAT -> Traefik IP.
	2. Traefik VIP equals the MetalLB IP advertised to the outside network.
	3. Ingress rules exist for the domain and return 200 for the ACME challenge path.

Verification commands
---------------------
Apply manifests (example):

```bash
kubectl apply -f gitops/my-app-service.yaml
kubectl apply -f gitops/my-app-ingress.yaml
```

Check services and ingresses:

```bash
kubectl get svc -A -o wide
kubectl get ingress -A
kubectl get certificate -n gitops
kubectl describe challenge -n gitops
```

Quick curl tests:

```bash
# Test ingress via Traefik IP using SNI
curl -vkI https://10.8.24.103 -H 'Host: app.example.com'

# Test domain (must resolve to public NAT)
curl -vkI https://app.example.com
```

Troubleshooting
---------------
- If `EXTERNAL-IP` for Traefik is `<pending>`, check MetalLB logs and IP pool:
	`kubectl get ipaddresspools,l2advertisements -n metallb-system -o yaml`
- If Let’s Encrypt challenge fails with `404`, it typically means DNS/NAT points to
	the wrong public IP (traffic reaching a different host or service). Align NAT
	to the Traefik VIP.
- Avoid assigning the same `loadBalancerIP` to two services — MetalLB will refuse
	allocation and the service will show allocation errors.

Best practices
--------------
- Reserve a small documented range of MetalLB IPs for public-facing ingress VIPs and
	another range for internal/admin services. Record them in a repo file when changed.
- Keep `ingressClassName: traefik` in all public ingresses and `cert-manager.io/cluster-issuer` set to
	`https-issuer` to enable automatic TLS.

Files to edit
-------------
- Add service/ingress manifests under the `gitops/` folder so ArgoCD will pick them up.
- Update this README if you add or change the MetalLB IP plan.

If you want, I can add a `gitops/ip-plan.md` with assigned IPs and reserve a set for
Traefik VIPs vs internal services.


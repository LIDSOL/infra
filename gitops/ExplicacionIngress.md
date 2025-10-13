# Explicación de Ingress deployment
El archivo `ingress-deployment` se encarga de desplegar el ingress-nginx controller en el cluster:

* Crea el namespace _ingress-nginx_ para los componentes de ingress
* Crea Service Accounts _ingress-nginx_, _ingress-nginx-admission_ y les vincula sus respectivos roles
* Crea los pods del controller con la imagen `registry.k8s.io/ingress-nginx/controller:v1.13.2` y ports asociados: 80 (HTTP), 443 (HTTPS), 8443 (webhook)
* Despliega el servicio _ingress-nginx-controller_ de tipo LoadBalancer, exponiendo los ports: 80 (HTTP), 443 (HTTPS)
* Despliega recursos para validar las configuraciones de ingress (sistema de webhook)
* Establece que los recursos ingress con el atributo `ingressClassName: nginx` han de ser manejados por el controller

Para conseguir que el _ingress-nginx-controller_ funcione como reverse proxy para un servicio, se debe crear un recurso de tipo `Ingress` con los siguientes atributos:

```
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ingress-para-servicio-x
spec:
  ingressClassName: nginx
  rules:
  # el dominio mediante el cual se desea acceder al servicio como db.lidsol.unam.mx
  - host: nombre.ejemplo.com 
    http:
      paths:
      # path del dominio, ej. db.lidsol.unam.mx/foo
      - path: /foo
        pathType: Prefix
        backend:
          service:
            name: nombre-del-servicio
            # el port expuesto por el servicio ej. 80
            port:
              number: 80
```
[documentación de ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/)

[documentación de ingress-nginx](https://kubernetes.github.io/ingress-nginx/deploy/$0)

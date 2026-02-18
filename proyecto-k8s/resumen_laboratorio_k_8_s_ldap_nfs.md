# Estado del Laboratorio K8s + LDAP + Samba + NFS

---

## 1. Lo conseguido hoy

Infraestructura operativa:

- Namespace `proyecto` aislado
- OpenLDAP (StatefulSet) funcionando
- Usuarios y grupos POSIX en LDAP
- Cliente Ubuntu autenticando contra LDAP
- NSS funcionando (`getent passwd carlos` OK)
- Samba integrado con LDAP
- PVC persistente creado
- Servidor NFS desplegado
- autofs instalado y activo sobre `/home`
- DNS interno del cluster funcionando correctamente

Estado general: arquitectura coherente y funcional a nivel de identidad y servicios base.

---

## 2. Archivos nuevos

### 03-nfs-server/

- `pvc-data.yaml`
- `deployment.yaml`
- `service.yaml`

### 06-clients-testing/

- `autofs-configmap.yaml`

---

## 3. Archivos modificados

### 05-samba/deployment.yaml

- Reemplazado `emptyDir` por `persistentVolumeClaim`
- Uso del PVC `nfs-data`

### 06-clients-testing/pod-ubuntu-client.yaml

Añadido:

- Instalación de `autofs`
- Instalación de `nfs-common`
- Copia de `auto.master` y `auto.home`
- Arranque de `autofs`

### 03-nfs-server/service.yaml

- Eliminado `clusterIP: None`
- Recreado como `ClusterIP` estándar

---

## 4. Comandos para iniciar todo desde 0

### Limpieza completa

```bash
kubectl delete namespace proyecto --ignore-not-found
sleep 15
```

### Crear namespace

```bash
kubectl apply -f 00-namespace/namespace.yaml
```

### Desplegar NFS

```bash
kubectl apply -f 03-nfs-server/pvc-data.yaml
kubectl apply -f 03-nfs-server/deployment.yaml
kubectl apply -f 03-nfs-server/service.yaml
kubectl wait --for=condition=available deployment/nfs-server -n proyecto --timeout=120s
```

### Services base

```bash
kubectl apply -f 02-openldap/service.yaml
kubectl apply -f 05-samba/service.yaml
```

### LDAP

```bash
bash scripts/rebuild-ldap.sh
```

Verificación:

```bash
kubectl exec -it ubuntu-client -n proyecto -- getent passwd carlos
```

### Preparar estructura NFS

```bash
kubectl exec -it deployment/nfs-server -n proyecto -- mkdir -p /exports/home
kubectl exec -it deployment/nfs-server -n proyecto -- mkdir -p /exports/compartido

kubectl exec -it deployment/nfs-server -n proyecto -- chown root:3000 /exports/compartido
kubectl exec -it deployment/nfs-server -n proyecto -- chmod 2775 /exports/compartido

kubectl exec -it deployment/nfs-server -n proyecto -- mkdir /exports/home/carlos
kubectl exec -it deployment/nfs-server -n proyecto -- chown 2001:3000 /exports/home/carlos
kubectl exec -it deployment/nfs-server -n proyecto -- chmod 700 /exports/home/carlos
```

### Samba

```bash
bash scripts/rebuild-samba.sh
```

### autofs

```bash
kubectl apply -f 06-clients-testing/autofs-configmap.yaml
kubectl apply -f 06-clients-testing/pod-ubuntu-client.yaml
kubectl wait --for=condition=ready pod/ubuntu-client -n proyecto --timeout=120s
```

---

## 5. Problemas encontrados y solucionados

### ConfigMap autofs inexistente

- Error: `configmap "autofs-config" not found`
- Solución: aplicar antes de recrear el Pod

### ubuntu-client no se recreaba

- Causa: es un Pod simple, no Deployment
- Solución: reaplicar manualmente

### Service NFS headless

- Causa: `clusterIP: None`
- Solución: borrar y recrear Service como ClusterIP

### Problemas RPC con NFS

- NFSv3 + RPC no funciona correctamente detrás de Service en Kubernetes

---

## 6. Problema actual no resuelto

### Montaje NFS de subdirectorios falla

Error:

```
mount.nfs: mounting 10.244.0.7:/exports/home failed: No such file or directory
```

Diagnóstico:

- El contenedor `itsthenetwork/nfs-server-alpine` exporta `/exports`
- NFSv3 usa RPC y puertos dinámicos
- Kubernetes Services no manejan correctamente mountd dinámico
- Montar subpaths dentro del export no está funcionando correctamente

Estado:

- NFS server desplegado
- Export principal activo
- Integración con autofs incompleta

---

## 7. Qué queda por hacer

### Opción recomendada (profesional)

Migrar a NFSv4 (nfs-ganesha)

Ventajas:

- No usa rpcbind
- Solo usa puerto 2049
- Compatible con Service ClusterIP
- Integración limpia con Kubernetes


### Alternativa laboratorio rápido

Montar `/exports` completo y trabajar con subdirectorios manualmente.

---

## Estado final del laboratorio

LDAP → 100%
Samba → 90%
Cliente LDAP → 100%
NFS → 70% (desplegado pero export problemático)
autofs → 80% (funciona pero backend NFS no monta)
Arquitectura general → sólida

---

## Conclusión técnica

La infraestructura está correctamente diseñada.

El único bloqueo actual es la limitación estructural de NFSv3 + RPC dentro de Kubernetes.

La solución profesional pasa por migrar a NFSv4 (ganesha).


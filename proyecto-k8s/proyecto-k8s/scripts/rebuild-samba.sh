#!/bin/bash

NAMESPACE="proyecto"
SAMBA_DIR="$HOME/proyecto-k8s/05-samba"



#=========================================================================================================================

# Renovamos el deploy de samba

echo "=== 1. Borrando versioon anterior de samba ==="
kubectl delete deployment samba-server -n $NAMESPACE 2>/dev/null
kubectl delete configmap samba-config -n $NAMESPACE 2>/dev/null


echo "=== 2. Desplegando nueva version de samba ==="
kubectl apply -f $SAMBA_DIR/configmap-smb.yaml -n $NAMESPACE
kubectl apply -f $SAMBA_DIR/deployment.yaml -n $NAMESPACE


#=========================================================================================================================



# Esperamos a que el pod arranque con wait, (mismo truco que el script rebuild-ldap.sh) (timeout importante para que no se cuelgue)

echo "=== 3. Esperando a que el Pod arranque... ==="
kubectl wait --for=condition=available deployment/samba-server -n $NAMESPACE --timeout=60s




# Una vez iniciado, obtenemos el nombre y esperamos una respuesta del fs del contenedor para asegurar que samba esta listo

POD_NAME=$(kubectl get pod -l app=samba -n $NAMESPACE -o jsonpath="{.items[0].metadata.name}")

echo "=== Esperando respuesta del contenedor ==="
until kubectl exec $POD_NAME -n $NAMESPACE -- ls /etc/samba/smb.conf >/dev/null 2>&1; do
    echo -n "#"
    sleep 2
done
echo "Listo"


#==========================================================================================================================


# Esto es importante, ya que la imagen de samba que estamos usando no tiene configurado el nuestro SID ni la identidad LDAP
# Por lo que hay que configurarlo a mano. Digamos que cada reinicio asigna un SID aleatorio

echo "=== 4. Configurando SID e Identidad LDAP ==="

# 1. Fijar SID
echo " -> Fijando SID del dominio..."
kubectl exec $POD_NAME -n $NAMESPACE -- net setlocalsid S-1-5-21-1234567890-1234567890-1234567890
kubectl exec $POD_NAME -n $NAMESPACE -- net setdomainsid INF S-1-5-21-1234567890-1234567890-1234567890



#==========================================================================================================================


# Anadimos la contrasena ldap para que samba se conecte a ldap y compruebe que la contrasena de carlos es la correcta
# Sin esto, ldap no dejara acceder a samba a su base de datos
# Lo guarda en un archivo binario llamado secrets.tdb

echo " -> Inyectando secreto LDAP del Admin..."
kubectl exec $POD_NAME -n $NAMESPACE -- smbpasswd -w lasquepasancosas

# Creamos el usuario carlos en el pod samba, sin esto, aunque a nivel de servicio, el usuario carlos es reconocido por samba gracias a ldap
# A nivel de sistema operativo, el usuario no existe y no podra acceder a los recursos compartidos 

echo " -> Creando usuario Unix 'carlos' en el contenedor..."
kubectl exec $POD_NAME -n $NAMESPACE -- adduser --uid 2001 --disabled-password --gecos "" carlos


#==========================================================================================================================



# Estp genera el hash de la contrasena de carlos y lo inyecta en samba, sin esto, aunque el usuario carlos exista a nivel de sistema operativo, no podra autenticarse en samba
echo " -> Sincronizando hashes de Samba para Carlos..."
kubectl exec $POD_NAME -n $NAMESPACE -- sh -c "printf 'carlos\ncarlos\n' | smbpasswd -a carlos"

if [ $? -eq 0 ]; then
    echo "TODO CONFIGURADO"
    echo "Prueba ahora desde ubuntu-client:"
    echo "kubectl exec -it ubuntu-client -n $NAMESPACE -- smbclient -L //samba-server -U carlos%carlos"
else
    echo "Fallo la configuracion de samba"
fi


#==========================================================================================================================



# Se crea el grupo alumnos dentro del contenedor samba, sin esto, aunque el grupo alumnos exista a nivel de servicio, no existira a nivel de sistema operativo y no podra ser asignado a los recursos compartidos. (se anade a carlos a este grupo)

kubectl exec $POD_NAME -n $NAMESPACE -- addgroup --gid 3000 alumnos

kubectl exec $POD_NAME -n $NAMESPACE -- adduser carlos alumnos


echo "Instalando el cliente de samba en el pod ubuntu"


kubectl exec -it ubuntu-client -n proyecto -- apt-get update
kubectl exec -it ubuntu-client -n proyecto -- apt-get install -y smbclient

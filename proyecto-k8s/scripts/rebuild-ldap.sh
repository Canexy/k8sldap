#!/bin/bash


NAMESPACE="proyecto"
LDAP_DIR="$HOME/proyecto-k8s/02-openldap"

echo " -=-=- 1. Limpieza del pod ldap, ubuntu y del volumen de la base de datos -=-=- "



# sts significa statefulset
# Usamos --force y --grace-period=0 para eliminar inmediatamente el statefulset y sus pods asociados (para que no queden en estado Terminating)
# --ignore-not-found para evitar errores y que no se cierre el script si no existen

kubectl delete sts openldap -n $NAMESPACE --force --grace-period=0 2>/dev/null
kubectl delete pvc ldap-data-openldap-0 -n $NAMESPACE --ignore-not-found
kubectl delete pod ubuntu-client -n $NAMESPACE --ignore-not-found



# ========================================================================================================================

# El pvc no se borra instantaneamente, esperamos para que no haya conflictos de nombre al crear uno nuevo

echo " -=-=- 2. Borrando el pvc del ldap ( ~= 15s) -=-=- "
sleep 15


#=========================================================================================================================


# Esta parte del codigo borra el configmap en 02-openldap y crea uno nuevo al vuelo con los archivos ldif que se encuentran en esa carpeta. 
# Es importante que los archivos ldif estén en esa carpeta y que el configmap se llame ldap-seed-data, 
# ya que el statefulset.yaml hace referencia a ese configmap para montar los archivos de siembra en el contenedor del servidor LDAP.


echo "-=-=- 3.Reseteamos configmap  -=-=-"
cd $LDAP_DIR
kubectl delete configmap ldap-seed-data -n $NAMESPACE 2>/dev/null
kubectl create configmap ldap-seed-data -n $NAMESPACE $(ls *.ldif | awk '{print "--from-file=" $1}') # Esto ultimo permite crear archivos ldif al vuelo
kubectl apply -f $HOME/proyecto-k8s/06-clients-testing/client-configmap.yaml -n $NAMESPACE


#=========================================================================================================================




echo "-=-=- 4. Desplegamos pod ldap y cliente ubuntu -=-=-"
kubectl apply -f statefulset.yaml -n $NAMESPACE
kubectl apply -f $HOME/proyecto-k8s/06-clients-testing/pod-ubuntu-client.yaml 2>/dev/null



#==========================================================================================================================



# Esperamos que el pod ldap en concreto, este listo antes de sembrar datos
# timeout de 120s para evitar que se cuelgue para siempre

echo "-=-=- 5. Esperando que el servidor esté listo -=-=-"
kubectl wait --for=condition=ready pod/openldap-0 -n $NAMESPACE --timeout=120s
sleep 10



#==========================================================================================================================


# Super importante el orden alfanumerico para que el primer ldif en ejecutarse sea el de la estructura base (01-...)

# Tambien importante excluir el ldif de permisos ya que este se aplica con ldapmodify y no con ldapadd (grep -v para excluirlo)

echo "-=-=- 6. Sembrado los datos (.ldif) -=-=-"
for f in $(ls *.ldif | grep -v "permissions" | sort); do
    echo " -> Aplicando $f..."
    cat "$f" | kubectl exec -i openldap-0 -n $NAMESPACE -- ldapadd -x -D "cn=admin,dc=inf" -w lasquepasancosas 2>/dev/null
done



#==========================================================================================================================


# Ahora es donde aplicamos los permisos con ldapmodify

echo "-=-=- 7. Aplicando permisos (ACLs) -=-=-"
cat 06-permissions.ldif | kubectl exec -i openldap-0 -n $NAMESPACE -- ldapmodify -Y EXTERNAL -H ldapi:///


#==========================================================================================================================


# Buscamos a Carlos en el servidor LDAP y desde el cliente Ubuntu, aunque esto nunca llega a funcionar a la primera ya que el cliente necesita un tiempo para actualizar su cache NSS

#echo "-=-=- 8. Verificación Final -=-=-"
#echo "Buscando a Carlos en el servidor..."
#kubectl exec -i openldap-0 -n $NAMESPACE -- ldapsearch -x -b "dc=inf" "(uid=carlos)" | grep "dn:"


#==========================================================================================================================




#echo "Buscando a Carlos desde el nuevo cliente..."
#sleep 5
#kubectl exec -i ubuntu-client -n $NAMESPACE -- getent passwd carlos

echo "-=-=- 8. Verificación Final -=-=-"


echo ""
echo "Ejecute: kubectl exec -i ubuntu-client -n proyecto -- getent passwd carlos"
echo "para verificar desde el cliente ubuntu que el usuario carlos existe"
echo ""

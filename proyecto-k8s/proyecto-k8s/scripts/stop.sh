#!/bin/bash

echo "Lanzando limpieza desde la raíz del proyecto..."

for d in */; do
    if ls "$d"*.yaml >/dev/null 2>&1; then
        kubectl delete -f "$d" --ignore-not-found
    fi
done

if ls *.yaml >/dev/null 2>&1; then
    kubectl delete -f . --ignore-not-found
fi

kubectl delete pvc --all -n proyecto --ignore-not-found

echo "Limpieza completada."

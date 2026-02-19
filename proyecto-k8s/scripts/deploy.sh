#!/bin/bash


kubectl apply -f 00*/*

~/proyecto-k8s/scripts/rebuild-samba.sh && ~/proyecto-k8s/scripts/rebuild-ldap.sh

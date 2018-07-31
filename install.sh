#!/bin/bash

API_SERVER_CFG=/etc/kubernetes/manifests/kube-apiserver.yaml 

if ! grep -q PodPreset $API_SERVER_CFG; then
  sed -i 's/--admission-control=.*/&,PodPreset\n    - --runtime-config=settings.k8s.io\/v1alpha1=true/g' $API_SERVER_CFG
fi

sleep 15

kubectl apply -f lxcfs.yaml 

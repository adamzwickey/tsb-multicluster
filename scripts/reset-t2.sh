#!/usr/bin/env bash
: ${VARS_YAML?"Need to set VARS_YAML environment variable"}

export GATEWAY_IP=$(kubectl get service tsb-gateway-bookinfo -n bookinfo -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
kubectl apply -n bookinfo -f bookinfo/bookinfo.yaml
while kubectl get po -n bookinfo | grep Running | wc -l | grep 7 ; [ $? -ne 0 ]; do
    echo Bookinfo is not yet ready
    sleep 5s
done
kubectl apply -f bookinfo/tmp.yaml
for i in {1..50}
do
   curl -vv http://$GATEWAY_IP/productpage\?u=normal
done
kubectl delete -f bookinfo/tmp.yaml
kubectl apply -n bookinfo -f bookinfo/bookinfo-multi.yaml
k delete po -n bookinfo -l app=tsb-gateway-bookinfo
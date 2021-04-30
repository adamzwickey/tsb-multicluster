#!/usr/bin/env bash
: ${VARS_YAML?"Need to set VARS_YAML environment variable"}

echo "Deploying Bookinfo Application"
kubectl create ns bookinfo
kubectl apply -n bookinfo -f bookinfo/bookinfo.yaml
kubectl apply -n bookinfo -f bookinfo/cluster-ingress-gw.yaml
kubectl -n bookinfo create secret tls bookinfo-certs \
    --key $(yq r $VARS_YAML k8s.bookinfoCertDir)/privkey.pem \
    --cert $(yq r $VARS_YAML k8s.bookinfoCertDir)/fullchain.pem
while kubectl get po -n bookinfo | grep Running | wc -l | grep 7 ; [ $? -ne 0 ]; do
    echo Bookinfo is not yet ready
    sleep 5s
done
while kubectl get service tsb-gateway-bookinfo -n bookinfo | grep pending | wc -l | grep 0 ; [ $? -ne 0 ]; do
    echo Gateway IP not assigned
    sleep 5s
done
export GATEWAY_IP=$(kubectl get service tsb-gateway-bookinfo -n bookinfo -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
kubectl apply -f bookinfo/tmp.yaml
for i in {1..50}
do
    curl -vv http://$GATEWAY_IP/productpage\?u=normal
done
kubectl delete -f bookinfo/tmp.yaml
kubectl apply -n bookinfo -f bookinfo/bookinfo-multi.yaml

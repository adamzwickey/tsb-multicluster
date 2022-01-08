#!/usr/bin/env bash
: ${VARS_YAML?"Need to set VARS_YAML environment variable"}

echo "Deploying Bookinfo Application"
kubectl create ns bookinfo
kubectl apply -n bookinfo -f bookinfo/cluster-ingress-gw.yaml
kubectl apply -n bookinfo -f bookinfo/bookinfo-multi.yaml
kubectl -n bookinfo create secret tls bookinfo-certs \
    --key $(yq eval .k8s.bookinfoCertDir $VARS_YAML)/privkey.pem \
    --cert $(yq eval .k8s.bookinfoCertDir $VARS_YAML)/fullchain.pem
while kubectl get po -n bookinfo | grep Running | wc -l | grep 7 ; [ $? -ne 0 ]; do
    echo Bookinfo is not yet ready
    sleep 5
done
while kubectl get service tsb-gateway -n bookinfo | grep pending | wc -l | grep 0 ; [ $? -ne 0 ]; do
    echo Gateway IP not assigned
    sleep 5
done
# export GATEWAY_IP=$(kubectl get service tsb-gateway -n bookinfo -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
# kubectl apply -f bookinfo/tmp.yaml
# for i in {1..50}
# do
#     curl -vv http://$GATEWAY_IP/productpage\?u=normal
# done
# kubectl delete -f bookinfo/tmp.yaml
# kubectl apply -n bookinfo -f bookinfo/bookinfo-multi.yaml

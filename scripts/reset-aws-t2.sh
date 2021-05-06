#!/usr/bin/env bash
: ${VARS_YAML?"Need to set VARS_YAML environment variable"}

export GATEWAY_IP=$(kubectl get service tsb-gateway-bookinfo -n bookinfo -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
kubectl apply -n bookinfo -f bookinfo/bookinfo.yaml
sleep 5s
while kubectl get po -n bookinfo | grep Running | wc -l | grep 7 ; [ $? -ne 0 ]; do
    echo Bookinfo is not yet ready
    sleep 5s
done
kubectl apply -f bookinfo/tmp.yaml
kubectl run test -n default --restart Never --rm -i --tty --image tutum/curl -- sh -c 'for i in $(seq 1 50); do curl -vvv --connect-timeout 2 http://productpage.bookinfo.svc.cluster.local:9080/productpage?u=normal; done'
kubectl delete -f bookinfo/tmp.yaml
kubectl apply -n bookinfo -f bookinfo/bookinfo-multi.yaml
kubectl delete po -n bookinfo -l app=tsb-gateway-bookinfo
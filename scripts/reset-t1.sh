#!/usr/bin/env bash
: ${VARS_YAML?"Need to set VARS_YAML environment variable"}

export T1_GATEWAY_IP=$(kubectl get service tsb-tier1 -n t1 -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
kubectl apply -f bookinfo/tmp1.yaml
for i in {1..50}
do
   curl -vv http://$T1_GATEWAY_IP
done
kubectl delete -f bookinfo/tmp1.yaml
sleep 10
kubectl delete po --selector='app=tsb-tier1'
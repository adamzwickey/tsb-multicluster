#!/usr/bin/env bash
: ${VARS_YAML?"Need to set VARS_YAML environment variable"}
echo config YAML:
cat $VARS_YAML

gcloud container clusters get-credentials $(yq r $VARS_YAML gcp.mgmt.clusterName) \
   --region $(yq r $VARS_YAML gcp.mgmt.region) --project $(yq r $VARS_YAML gcp.env)
kubectl delete po -n istio-system -l app=edge
kubectl delete po -n t1 -l app=tsb-tier1

gcloud container clusters get-credentials $(yq r $VARS_YAML gcp.workload1.clusterName) \
   --region $(yq r $VARS_YAML gcp.workload1.region) --project $(yq r $VARS_YAML gcp.env)
kubectl delete po -n istio-system -l app=edge
kubectl delete po -n bookinfo -l app=tsb-gateway-bookinfo

gcloud container clusters get-credentials $(yq r $VARS_YAML gcp.workload2.clusterName) \
   --region $(yq r $VARS_YAML gcp.workload2.region) --project $(yq r $VARS_YAML gcp.env)
kubectl delete po -n istio-system -l app=edge
kubectl delete po -n bookinfo -l app=tsb-gateway-bookinfo

aws eks --region us-east-2 update-kubeconfig \
    --name $(yq r $VARS_YAML aws.workload1.clusterName) 
kubectl delete po -n istio-system -l app=edge
kubectl delete po -n bookinfo -l app=tsb-gateway-bookinfo

gcloud container clusters get-credentials $(yq r $VARS_YAML gcp.workload1.clusterName) \
   --region $(yq r $VARS_YAML gcp.workload1.region) --project $(yq r $VARS_YAML gcp.env)
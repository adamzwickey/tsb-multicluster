#!/usr/bin/env bash
: ${VARS_YAML?"Need to set VARS_YAML environment variable"}
echo config YAML:
cat $VARS_YAML

#T1
gcloud container clusters get-credentials $(yq r $VARS_YAML gcp.mgmt.clusterName) \
   --region $(yq r $VARS_YAML gcp.mgmt.region) --project $(yq r $VARS_YAML gcp.env)
kubectl delete po -n istio-system -l app=edge
kubectl delete po -n t1 -l app=tsb-tier1

ENABLED=$(yq r $VARS_YAML gcp.workload1.deploy)
if [ "$ENABLED" = "true" ];
then
   gcloud container clusters get-credentials $(yq r $VARS_YAML gcp.workload1.clusterName) \
      --region $(yq r $VARS_YAML gcp.workload1.region) --project $(yq r $VARS_YAML gcp.env)
   kubectl delete po -n istio-system -l app=edge
   kubectl delete po -n bookinfo -l app=tsb-gateway-bookinfo
else
  echo "Skipping GCP Workload Cluster 1"
fi

ENABLED=$(yq r $VARS_YAML gcp.workload2.deploy)
if [ "$ENABLED" = "true" ];
then
   gcloud container clusters get-credentials $(yq r $VARS_YAML gcp.workload2.clusterName) \
      --region $(yq r $VARS_YAML gcp.workload2.region) --project $(yq r $VARS_YAML gcp.env)
   kubectl delete po -n istio-system -l app=edge
   kubectl delete po -n bookinfo -l app=tsb-gateway-bookinfo
else
  echo "Skipping GCP Workload Cluster 2"
fi

ENABLED=$(yq r $VARS_YAML aws.workload1.deploy)
if [ "$ENABLED" = "true" ];
then
   rapture assume tetrate-test/admin
   aws eks --region $(yq r $VARS_YAML aws.workload1.region) update-kubeconfig \
    --name $(yq r $VARS_YAML aws.workload1.clusterName) 
   kubectl delete po -n istio-system -l app=edge
   kubectl delete po -n bookinfo -l app=tsb-gateway-bookinfo
else
  echo "Skipping AWS Workload Cluster 1"
fi

ENABLED=$(yq r $VARS_YAML aws.workload2.deploy)
if [ "$ENABLED" = "true" ];
then
   rapture assume tetrate-test/admin
   aws eks --region $(yq r $VARS_YAML aws.workload2.region) update-kubeconfig \
    --name $(yq r $VARS_YAML aws.workload2.clusterName) 
   kubectl delete po -n istio-system -l app=edge
   kubectl delete po -n bookinfo -l app=tsb-gateway-bookinfo 
else
  echo "Skipping AWS Workload Cluster 2"
fi

ENABLED=$(yq r $VARS_YAML azure.workload1.deploy)
if [ "$ENABLED" = "true" ];
then
   az aks get-credentials --resource-group $(yq r $VARS_YAML azure.workload1.resourceGroup)\
    --name $(yq r $VARS_YAML azure.workload1.clusterName)
   kubectl delete po -n istio-system -l app=edge
   kubectl delete po -n bookinfo -l app=tsb-gateway-bookinfo
else
  echo "Skipping Azure Workload Cluster 1"
fi

ENABLED=$(yq r $VARS_YAML azure.workload2.deploy)
if [ "$ENABLED" = "true" ];
then
   az aks get-credentials --resource-group $(yq r $VARS_YAML azure.workload2.resourceGroup)\
    --name $(yq r $VARS_YAML azure.workload2.clusterName)
   kubectl delete po -n istio-system -l app=edge
   kubectl delete po -n bookinfo -l app=tsb-gateway-bookinfo
else
  echo "Skipping Azure Workload Cluster 2"
fi

gcloud container clusters get-credentials $(yq r $VARS_YAML gcp.workload1.clusterName) \
   --region $(yq r $VARS_YAML gcp.workload1.region) --project $(yq r $VARS_YAML gcp.env)

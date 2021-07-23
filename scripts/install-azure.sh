#!/usr/bin/env bash
: ${VARS_YAML?"Need to set VARS_YAML environment variable"}

ENABLED=$(yq r $VARS_YAML azure.workload1.deploy)
if [ "$ENABLED" = "true" ];
then
  echo "Deploying Azure Workload Cluster 1"
  az account set --subscription $(yq r $VARS_YAML azure.subscription)
  az login
  az group create --name $(yq r $VARS_YAML azure.workload1.resourceGroup) \
    --location $(yq r $VARS_YAML azure.workload1.region)
  az aks create --resource-group $(yq r $VARS_YAML azure.workload1.resourceGroup) \
    --name $(yq r $VARS_YAML azure.workload1.clusterName) \
    --min-count 2 --max-count 6 --enable-cluster-autoscaler \
    --node-vm-size Standard_B4ms
  
  source ./scripts/onboard-to-mp.sh \
    $(yq r $VARS_YAML azure.workload1.clusterName) \
    $(yq r $VARS_YAML azure.workload1.region)
  #Change context back
  az aks get-credentials --resource-group $(yq r $VARS_YAML azure.workload1.resourceGroup)\
    --name $(yq r $VARS_YAML azure.workload1.clusterName)
  source ./scripts/deploy-cp.sh \
    $(yq r $VARS_YAML azure.workload1.clusterName) 
  source ./scripts/deploy-bookinfo.sh
  
else
  echo "Skipping Azure Workload Cluster 1"
fi

ENABLED=$(yq r $VARS_YAML azure.workload2.deploy)
if [ "$ENABLED" = "true" ];
then
  echo "Deploying Azure Workload Cluster 2"
  az account set --subscription $(yq r $VARS_YAML azure.subscription)
  az login
  az group create --name $(yq r $VARS_YAML azure.workload2.resourceGroup) \
    --location $(yq r $VARS_YAML azure.workload2.region)
  az aks create --resource-group $(yq r $VARS_YAML azure.workload2.resourceGroup) \
    --name $(yq r $VARS_YAML azure.workload2.clusterName) \
    --min-count 2 --max-count 6 --enable-cluster-autoscaler \
    --node-vm-size Standard_B4ms

  source ./scripts/onboard-to-mp.sh \
    $(yq r $VARS_YAML azure.workload2.clusterName) \
    $(yq r $VARS_YAML azure.workload2.region)
  #Change context back
  az aks get-credentials --resource-group $(yq r $VARS_YAML azure.workload2.resourceGroup)\
    --name $(yq r $VARS_YAML azure.workload2.clusterName)
  source ./scripts/deploy-cp.sh \
    $(yq r $VARS_YAML azure.workload2.clusterName) 
  source ./scripts/deploy-bookinfo.sh
else
  echo "Skipping Azure Workload Cluster 2"
fi
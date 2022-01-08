#!/usr/bin/env bash
: ${VARS_YAML?"Need to set VARS_YAML environment variable"}

ENABLED=$(yq r $VARS_YAML azure.workload1.deploy)
if [ "$ENABLED" = "true" ];
then
  echo "Deploying Azure Workload Cluster 1"
  az account set --subscription $(yq e .azure.subscription $VARS_YAML)
  az login
  az group create --name $(yq e .azure.workload1.resourceGroup $VARS_YAML) \
    --location $(yq e .azure.workload1.region $VARS_YAML)
  az aks create --resource-group $(yq e .azure.workload1.resourceGroup $VARS_YAML) \
    --name $(yq e .azure.workload1.clusterName $VARS_YAML) \
    --min-count 2 --max-count 6 --enable-cluster-autoscaler \
    --node-vm-size Standard_B4ms
  
  source ./scripts/onboard-to-mp.sh \
    $(yq e .azure.workload1.clusterName $VARS_YAML) \
    $(yq e .azure.workload1.region $VARS_YAML)
  #Change context back
  az aks get-credentials --resource-group $(yq e .azure.workload1.resourceGroup $VARS_YAML)\
    --name $(yq e .azure.workload1.clusterName $VARS_YAML)
  source ./scripts/deploy-cp.sh \
    $(yq e .azure.workload1.clusterName $VARS_YAML) 
  source ./scripts/deploy-bookinfo.sh
  
else
  echo "Skipping Azure Workload Cluster 1"
fi

ENABLED=$(yq r $VARS_YAML azure.workload2.deploy)
if [ "$ENABLED" = "true" ];
then
  echo "Deploying Azure Workload Cluster 2"
  az account set --subscription $(yq e .azure.subscription $VARS_YAML)
  az login
  az group create --name $(yq e .azure.workload2.resourceGroup $VARS_YAML) \
    --location $(yq e .azure.workload2.region $VARS_YAML)
  az aks create --resource-group $(yq e .azure.workload2.resourceGroup $VARS_YAML) \
    --name $(yq e .azure.workload2.clusterName $VARS_YAML) \
    --min-count 2 --max-count 6 --enable-cluster-autoscaler \
    --node-vm-size Standard_B4ms
  
  source ./scripts/onboard-to-mp.sh \
    $(yq e .azure.workload2.clusterName $VARS_YAML) \
    $(yq e .azure.workload2.region $VARS_YAML)
  #Change context back
  az aks get-credentials --resource-group $(yq e .azure.workload2.resourceGroup $VARS_YAML)\
    --name $(yq e .azure.workload2.clusterName $VARS_YAML)
  source ./scripts/deploy-cp.sh \
    $(yq e .azure.workload2.clusterName $VARS_YAML) 
  source ./scripts/deploy-bookinfo.sh
else
  echo "Skipping Azure Workload Cluster 2"
fi
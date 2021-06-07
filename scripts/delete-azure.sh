#!/usr/bin/env bash
: ${VARS_YAML?"Need to set VARS_YAML environment variable"}
echo config YAML:
cat $VARS_YAML

#Azure
ENABLED=$(yq r $VARS_YAML azure.workload1.deploy)
if [ "$ENABLED" = "true" ];
then
  echo "Destroying $(yq r $VARS_YAML azure.workload1.clusterName)..."
  az aks delete --resource-group $(yq r $VARS_YAML azure.workload1.resourceGroup) \
    --name $(yq r $VARS_YAML azure.workload1.clusterName) --verbose
else
  echo "Skipping $(yq r $VARS_YAML azure.workload1.clusterName)"
fi
ENABLED=$(yq r $VARS_YAML azure.workload2.deploy)
if [ "$ENABLED" = "true" ];
then
  echo "Destroying $(yq r $VARS_YAML azure.workload2.clusterName)..."
  az aks delete --resource-group $(yq r $VARS_YAML azure.workload2.resourceGroup) \
    --name $(yq r $VARS_YAML azure.workload2.clusterName) --verbose
else
  echo "Skipping $(yq r $VARS_YAML azure.workload2.clusterName)"
fi
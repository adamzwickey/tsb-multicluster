#!/usr/bin/env bash
: ${VARS_YAML?"Need to set VARS_YAML environment variable"}
echo config YAML:
cat $VARS_YAML

#Azure
ENABLED=$(yq eval .azure.workload1.deploy $VARS_YAML)
if [ "$ENABLED" = "true" ];
then
  echo "Destroying $(yq eval .azure.workload1.clusterName $VARS_YAML)..."
  az aks delete --resource-group $(yq eval .azure.workload1.resourceGroup $VARS_YAML) \
    --name $(yq eval .azure.workload1.clusterName $VARS_YAML) --verbose
  tctl delete -f generated/$(yq eval .azure.workload1.clusterName $VARS_YAML)/cluster.yaml
else
  echo "Skipping $(yq eval .azure.workload1.clusterName $VARS_YAML)"
fi
ENABLED=$(yq eval .azure.workload2.deploy $VARS_YAML)
if [ "$ENABLED" = "true" ];
then
  echo "Destroying $(yq eval .azure.workload2.clusterName $VARS_YAML)..."
  az aks delete --resource-group $(yq eval .azure.workload2.resourceGroup $VARS_YAML) \
    --name $(yq eval .azure.workload2.clusterName $VARS_YAML) --verbose
  tctl delete -f generated/$(yq eval .azure.workload2.clusterName $VARS_YAML)/cluster.yaml
else
  echo "Skipping $(yq eval .azure.workload2.clusterName $VARS_YAML)"
fi
#!/usr/bin/env bash
: ${VARS_YAML?"Need to set VARS_YAML environment variable"}

ENABLED=$(yq r $VARS_YAML azure.workload1.deploy)
if [ "$ENABLED" = "true" ];
then
  echo "Deploying Azure Workload Cluster 1"
  #TODO -- create cluster
  source ./scripts/onboard-to-mp.sh \
    $(yq r $VARS_YAML azure.workload1.clusterName) \
    $(yq r $VARS_YAML azure.workload1.region)
  #Change context back
  source ./scripts/deploy-cp.sh \
    $(yq r $VARS_YAML azure.workload1.clusterName) 
  source ./scripts/deploy-bookinfo.sh
  
else
  echo "Skipping Azure Workload Cluster 1"
fi
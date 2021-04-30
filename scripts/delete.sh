#!/usr/bin/env bash
: ${VARS_YAML?"Need to set VARS_YAML environment variable"}
echo config YAML:
cat $VARS_YAML

#GCP
ENABLED=$(yq r $VARS_YAML gcp.workload1.deploy)
if [ "$ENABLED" = "true" ];
then
  echo "Destroying $(yq r $VARS_YAML gcp.workload1.clusterName)..."
  gcloud container clusters delete $(yq r $VARS_YAML gcp.workload1.clusterName) \
   --region $(yq r $VARS_YAML gcp.workload1.region) --quiet
else
  echo "Skipping $(yq r $VARS_YAML gcp.workload1.clusterName)"
fi
ENABLED=$(yq r $VARS_YAML gcp.workload2.deploy)
if [ "$ENABLED" = "true" ];
then
  echo "Destroying $(yq r $VARS_YAML gcp.workload2.clusterName)..."
  gcloud container clusters delete $(yq r $VARS_YAML gcp.workload2.clusterName) \
   --region $(yq r $VARS_YAML gcp.workload2.region) --quiet
else
  echo "Skipping $(yq r $VARS_YAML gcp.workload2.clusterName)"
fi

#AWS
ENABLED=$(yq r $VARS_YAML aws.workload1.deploy)
if [ "$ENABLED" = "true" ];
then
  echo "Destroying $(yq r $VARS_YAML aws.workload1.clusterName)..."
  rapture assume tetrate-test/admin
  eksctl delete cluster --region $(yq r $VARS_YAML aws.workload1.region) \
    --name $(yq r $VARS_YAML aws.workload1.clusterName) --wait
else
  echo "Skipping $(yq r $VARS_YAML aws.workload1.clusterName)"
fi
ENABLED=$(yq r $VARS_YAML aws.workload2.deploy)
if [ "$ENABLED" = "true" ];
then
  echo "Destroying $(yq r $VARS_YAML aws.workload2.clusterName)..."
  rapture assume tetrate-test/admin
  eksctl delete cluster --region $(yq r $VARS_YAML aws.workload2.region) \
    --name $(yq r $VARS_YAML aws.workload2.clusterName) --wait
else
  echo "Skipping $(yq r $VARS_YAML aws.workload2.clusterName)"
fi

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

#MP
ENABLED=$(yq r $VARS_YAML gcp.mgmt.deploy)
if [ "$ENABLED" = "true" ];
then
  echo "Destroying $(yq r $VARS_YAML gcp.mgmt.clusterName)..."
  gcloud container clusters delete $(yq r $VARS_YAML gcp.mgmt.clusterName) \
   --region $(yq r $VARS_YAML gcp.mgmt.region) --quiet
else
  echo "Skipping Mgmt Plane"
fi

gcloud beta compute --project=$(yq r $VARS_YAML gcp.env) instances delete $(yq r $VARS_YAML gcp.vm.name) \
  --zone=$(yq r $VARS_YAML gcp.vm.networkZone) --quiet
rm -rf ~/.ssh/known_hosts
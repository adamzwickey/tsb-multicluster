#!/usr/bin/env bash
: ${VARS_YAML?"Need to set VARS_YAML environment variable"}
echo config YAML:
cat $VARS_YAML

#GCP
source ./scripts/delete-gcp.sh

#AWS
source ./scripts/delete-aws.sh

#Azure
source ./scripts/delete-azure.sh

#MP
ENABLED=$(yq eval .gcp.mgmt.deploy $VARS_YAML)
if [ "$ENABLED" = "true" ];
then
  echo "Destroying $(yq eval .gcp.mgmt.clusterName $VARS_YAML)..."
  gcloud container clusters delete $(yq eval .gcp.mgmt.clusterName $VARS_YAML) \
   --region $(yq eval .gcp.mgmt.region $VARS_YAML) --quiet
else
  echo "Skipping Mgmt Plane"
fi
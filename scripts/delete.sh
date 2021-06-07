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
ENABLED=$(yq r $VARS_YAML gcp.mgmt.deploy)
if [ "$ENABLED" = "true" ];
then
  echo "Destroying $(yq r $VARS_YAML gcp.mgmt.clusterName)..."
  gcloud container clusters delete $(yq r $VARS_YAML gcp.mgmt.clusterName) \
   --region $(yq r $VARS_YAML gcp.mgmt.region) --quiet
else
  echo "Skipping Mgmt Plane"
fi
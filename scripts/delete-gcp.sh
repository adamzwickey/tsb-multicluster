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

gcloud beta compute --project=$(yq r $VARS_YAML gcp.env) instances delete $(yq r $VARS_YAML gcp.vm.name) \
  --zone=$(yq r $VARS_YAML gcp.vm.networkZone) --quiet
rm -rf ~/.ssh/known_hosts
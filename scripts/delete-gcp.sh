#!/usr/bin/env bash
: ${VARS_YAML?"Need to set VARS_YAML environment variable"}
echo config YAML:
cat $VARS_YAML

#GCP
ENABLED=$(yq eval .gcp.workload1.deploy $VARS_YAML)
if [ "$ENABLED" = "true" ];
then
  echo "Destroying $(yq eval .gcp.workload1.clusterName $VARS_YAML)..."
  gcloud container clusters delete $(yq eval .gcp.workload1.clusterName $VARS_YAML) \
   --region $(yq eval .gcp.workload1.region $VARS_YAML) --quiet
  tctl delete -f generated/$(yq eval .gcp.workload1.clusterName $VARS_YAML)/cluster.yaml
else
  echo "Skipping $(yq eval .gcp.workload1.clusterName $VARS_YAML)"
fi
ENABLED=$(yq eval .gcp.workload2.deploy $VARS_YAML)
if [ "$ENABLED" = "true" ];
then
  echo "Destroying $(yq eval .gcp.workload2.clusterName $VARS_YAML)..."
  gcloud container clusters delete $(yq eval .gcp.workload2.clusterName $VARS_YAML) \
   --region $(yq eval .gcp.workload2.region $VARS_YAML) --quiet
  tctl delete -f generated/$(yq eval .gcp.workload2.clusterName $VARS_YAML)/cluster.yaml
else
  echo "Skipping $(yq eval .gcp.workload2.clusterName $VARS_YAML)"
fi

gcloud beta compute --project=$(yq eval .gcp.env $VARS_YAML) instances delete $(yq eval .gcp.vm.name $VARS_YAML) \
  --zone=$(yq eval .gcp.vm.networkZone $VARS_YAML) --quiet
rm -rf ~/.ssh/known_hosts
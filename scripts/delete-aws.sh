#!/usr/bin/env bash
: ${VARS_YAML?"Need to set VARS_YAML environment variable"}
echo config YAML:
cat $VARS_YAML

#AWS
ENABLED=$(yq eval .aws.workload1.deploy $VARS_YAML)
if [ "$ENABLED" = "true" ];
then
  echo "Destroying $(yq eval .aws.workload1.clusterName $VARS_YAML)..."
  rapture assume tetrate-test/admin
  eksctl delete cluster --region $(yq eval .aws.workload1.region $VARS_YAML) \
    --name $(yq eval .aws.workload1.clusterName $VARS_YAML) --wait
  tctl delete -f generated/$(yq eval .aws.workload1.clusterName $VARS_YAML)/cluster.yaml
else
  echo "Skipping $(yq eval .aws.workload1.clusterName $VARS_YAML)"
fi
ENABLED=$(yq eval .aws.workload2.deploy $VARS_YAML)
if [ "$ENABLED" = "true" ];
then
  echo "Destroying $(yq eval .aws.workload2.clusterName $VARS_YAML)..."
  rapture assume tetrate-test/admin
  eksctl delete cluster --region $(yq eval .aws.workload2.region $VARS_YAML) \
    --name $(yq eval .aws.workload2.clusterName) --wait
  tctl delete -f generated/$(yq eval .aws.workload2.clusterName $VARS_YAML)/cluster.yaml
else
  echo "Skipping $(yq eval .aws.workload2.clusterName)"
fi
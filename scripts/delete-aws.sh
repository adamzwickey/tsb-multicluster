#!/usr/bin/env bash
: ${VARS_YAML?"Need to set VARS_YAML environment variable"}
echo config YAML:
cat $VARS_YAML

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
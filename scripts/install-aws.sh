#!/usr/bin/env bash
: ${VARS_YAML?"Need to set VARS_YAML environment variable"}

ENABLED=$(yq r $VARS_YAML aws.workload1.deploy)
if [ "$ENABLED" = "true" ];
then
  echo "Deploying AWS Workload Cluster 1"
  rapture assume tetrate-test/admin
  eksctl create cluster --region $(yq r $VARS_YAML aws.workload1.region) \
    --name $(yq r $VARS_YAML aws.workload1.clusterName) \
    --nodes-min 2 --nodes-max 6 --node-labels="owner=adam" 
  aws eks --region us-east-2 update-kubeconfig \
    --name $(yq r $VARS_YAML aws.workload1.clusterName)

  source ./scripts/onboard-to-mp.sh \
    $(yq r $VARS_YAML gcp.workload1.clusterName) \
    $(yq r $VARS_YAML gcp.workload1.region)

  #AWS Context
  aws eks --region $(yq r $VARS_YAML aws.workload1.region) \
    update-kubeconfig --name $(yq r $VARS_YAML aws.workload1.clusterName) 
  source ./scripts/deploy-cp.sh \
    $(yq r $VARS_YAML aws.workload1.clusterName) 
  source ./scripts/deploy-bookinfo.sh
else
  echo "Skipping aws Workload Cluster 1"
fi

ENABLED=$(yq r $VARS_YAML aws.workload2.deploy)
if [ "$ENABLED" = "true" ];
then
  echo "Deploying AWS Workload Cluster 2"
  rapture assume tetrate-test/admin
  eksctl create cluster --region $(yq r $VARS_YAML aws.workload2.region) \
    --name $(yq r $VARS_YAML aws.workload2.clusterName) \
    --nodes-min 2 --nodes-max 6 --node-labels="owner=adam" 
  aws eks --region $(yq r $VARS_YAML aws.workload2.region) \
    update-kubeconfig --name $(yq r $VARS_YAML aws.workload2.clusterName)

  source ./scripts/onboard-to-mp.sh \
    $(yq r $VARS_YAML gcp.workload2.clusterName) \
    $(yq r $VARS_YAML gcp.workload2.region)

  #AWS Context
  aws eks --region $(yq r $VARS_YAML aws.workload2.region) \
    update-kubeconfig --name $(yq r $VARS_YAML aws.workload2.clusterName) 
  source ./scripts/deploy-cp.sh \
    $(yq r $VARS_YAML aws.workload2.clusterName) 
  source ./scripts/deploy-bookinfo.sh
else
  echo "Skipping aws Workload Cluster 2"
fi
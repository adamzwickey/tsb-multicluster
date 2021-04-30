#!/usr/bin/env bash
: ${VARS_YAML?"Need to set VARS_YAML environment variable"}
: ${1?"Must supply cluster name arg"}
: ${2?"Must supply cluster region arg"}

CLUSTER_NAME=$1
REGION=$2
mkdir -p generated/$CLUSTER_NAME

echo "Onboarding Workload Cluster $CLUSTER_NAME to Management Plane"
gcloud container clusters get-credentials $(yq r $VARS_YAML gcp.mgmt.clusterName) \
   --region $(yq r $VARS_YAML gcp.mgmt.region) --project $(yq r $VARS_YAML gcp.env)
tctl install manifest cluster-operator \
  --registry $(yq r $VARS_YAML tetrate.registry) > generated/$CLUSTER_NAME/cp-operator.yaml
cp cluster.yaml generated/$CLUSTER_NAME/
yq write generated/$CLUSTER_NAME/cluster.yaml -i "spec.locality.region" $REGION
yq write generated/$CLUSTER_NAME/cluster.yaml -i "metadata.name" $CLUSTER_NAME
tctl apply -f generated/$CLUSTER_NAME/cluster.yaml
tctl install cluster-certs --cluster $CLUSTER_NAME > generated/$CLUSTER_NAME/cluster-certs.yaml
tctl install manifest control-plane-secrets --cluster $CLUSTER_NAME \
    --allow-defaults > generated/$CLUSTER_NAME/cluster-secrets.yaml

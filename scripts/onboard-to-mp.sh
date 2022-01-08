#!/usr/bin/env bash
: ${VARS_YAML?"Need to set VARS_YAML environment variable"}
: ${1?"Must supply cluster name arg"}
: ${2?"Must supply cluster region arg"}

export CLUSTER_NAME=$1
export REGION=$2
mkdir -p generated/$CLUSTER_NAME

echo "Onboarding Workload Cluster $CLUSTER_NAME to Management Plane; Region: $REGION"
gcloud container clusters get-credentials $(yq eval .gcp.mgmt.clusterName $VARS_YAML) \
   --region $(yq eval .gcp.mgmt.region $VARS_YAML) --project $(yq eval .gcp.env $VARS_YAML)
tctl install manifest cluster-operator \
  --registry $(yq eval .tetrate.registry $VARS_YAML) > generated/$CLUSTER_NAME/cp-operator.yaml
cp cluster.yaml generated/$CLUSTER_NAME/
yq e -i '.spec.locality.region=strenv(REGION) |
        .metadata.name=strenv(CLUSTER_NAME)' generated/$CLUSTER_NAME/cluster.yaml
tctl apply -f generated/$CLUSTER_NAME/cluster.yaml
tctl install cluster-certs --cluster $CLUSTER_NAME > generated/$CLUSTER_NAME/cluster-certs.yaml
tctl install manifest control-plane-secrets --cluster $CLUSTER_NAME \
    --allow-defaults > generated/$CLUSTER_NAME/cluster-secrets.yaml

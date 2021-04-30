#!/usr/bin/env bash
: ${VARS_YAML?"Need to set VARS_YAML environment variable"}
echo config YAML:
cat $VARS_YAML

DEPLOY_MP=$(yq r $VARS_YAML gcp.mgmt.deploy)
if [ "$DEPLOY_MP" = "true" ];
then
  echo "Deploying Management Plane"
  source ./scripts/install-mp.sh
  tctl apply -f bookinfo/workspace.yaml
else
  echo "Skipping Management Plane"
fi

GCP_ENABLED=$(yq r $VARS_YAML gcp.enabled)
if [ "$GCP_ENABLED" = "true" ];
then
  echo "Deploying GCP Workload clusters"
  source ./scripts/install-gcp.sh
else
  echo "Skipping GCP Workload clusters"
fi

AWS_ENABLED=$(yq r $VARS_YAML aws.enabled)
if [ "$AWS_ENABLED" = "true" ];
then
  echo "Deploying AWS Workload clusters"
  source ./scripts/install-aws.sh
else
  echo "Skipping AWS Workload clusters"
fi

AZ_ENABLED=$(yq r $VARS_YAML azure.enabled)
if [ "$AZ_ENABLED" = "true" ];
then
  echo "Deploying Azure Workload clusters"
  source ./scripts/install-azure.sh
else
  echo "Skipping Azure Workload clusters"
fi

KEYCLOAK_ENABLED=$(yq r $VARS_YAML keycloak.deploy)
if [ "$KEYCLOAK_ENABLED" = "true" ];
then
  echo "Deploying Keycloak"
  source ./scripts/deploy-keycloak.sh
else
  echo "Skipping Keycloak Deployment"
fi

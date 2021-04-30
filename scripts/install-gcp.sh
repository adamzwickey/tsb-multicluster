#!/usr/bin/env bash
: ${VARS_YAML?"Need to set VARS_YAML environment variable"}

ENABLED=$(yq r $VARS_YAML gcp.skipImages)
if [ "$ENABLED" = "false" ];
then
  echo "Syncing bintray images"
  tctl install image-sync --username $(yq r $VARS_YAML tetrate.apiUser) \
    --apikey $(yq r $VARS_YAML tetrate.apiKey) \
    --registry $(yq r $VARS_YAML tetrate.registry)
else
  echo "skipping image sync"
fi

ENABLED=$(yq r $VARS_YAML gcp.workload1.deploy)
if [ "$ENABLED" = "true" ];
then
  echo "Deploying GCP Workload Cluster 1..."
  gcloud container clusters create $(yq r $VARS_YAML gcp.workload1.clusterName) \
    --region $(yq r $VARS_YAML gcp.workload1.region) \
    --machine-type=$(yq r $VARS_YAML gcp.workload1.machineType) \
    --num-nodes=1 --min-nodes 0 --max-nodes 6 \
    --enable-autoscaling --enable-network-policy --release-channel=regular \
    --network "$(yq r $VARS_YAML gcp.workload1.network)" --subnetwork "$(yq r $VARS_YAML gcp.workload1.subNetwork)"
  gcloud container clusters get-credentials $(yq r $VARS_YAML gcp.workload1.clusterName) \
    --region $(yq r $VARS_YAML gcp.workload1.region) --project $(yq r $VARS_YAML gcp.env)
  
  source ./scripts/onboard-to-mp.sh \
    $(yq r $VARS_YAML gcp.workload1.clusterName) \
    $(yq r $VARS_YAML gcp.workload1.region)

  #Change Context back to workload cluster  
  gcloud container clusters get-credentials $(yq r $VARS_YAML gcp.workload1.clusterName) \
    --region $(yq r $VARS_YAML gcp.workload1.region) --project $(yq r $VARS_YAML gcp.env)
  source ./scripts/deploy-cp.sh \
    $(yq r $VARS_YAML gcp.workload1.clusterName) 
  source ./scripts/deploy-bookinfo.sh

else
  echo "Skipping GCP Workload Cluster 1"
fi

ENABLED=$(yq r $VARS_YAML gcp.workload2.deploy)
if [ "$ENABLED" = "true" ];
then
  echo "Deploying GCP Workload Cluster 2..."
  gcloud container clusters create $(yq r $VARS_YAML gcp.workload2.clusterName) \
    --region $(yq r $VARS_YAML gcp.workload2.region) \
    --machine-type=$(yq r $VARS_YAML gcp.workload2.machineType) \
    --num-nodes=1 --min-nodes 0 --max-nodes 6 \
    --enable-autoscaling --enable-network-policy --release-channel=regular \
    --network "$(yq r $VARS_YAML gcp.workload2.network)" --subnetwork "$(yq r $VARS_YAML gcp.workload2.subNetwork)"
  gcloud container clusters get-credentials $(yq r $VARS_YAML gcp.workload2.clusterName) \
    --region $(yq r $VARS_YAML gcp.workload2.region) --project $(yq r $VARS_YAML gcp.env)
  
  source ./scripts/onboard-to-mp.sh \
    $(yq r $VARS_YAML gcp.workload2.clusterName) \
    $(yq r $VARS_YAML gcp.workload2.region)

  #Change Context back to workload cluster  
  gcloud container clusters get-credentials $(yq r $VARS_YAML gcp.workload2.clusterName) \
    --region $(yq r $VARS_YAML gcp.workload2.region) --project $(yq r $VARS_YAML gcp.env)
  source ./scripts/deploy-cp.sh \
    $(yq r $VARS_YAML gcp.workload2.clusterName) 
  source ./scripts/deploy-bookinfo.sh
else
  echo "Skipping GCP Workload Cluster 2"
fi

ENABLED=$(yq r $VARS_YAML gcp.vm.deploy)
if [ "$ENABLED" = "true" ];
then
  echo "Deploying GCP VM for Mesh Expansion..."
  # Create VM
  gcloud beta compute --project=$(yq r $VARS_YAML gcp.env) instances create $(yq r $VARS_YAML gcp.vm.name) \
    --zone=$(yq r $VARS_YAML gcp.vm.networkZone) --subnet=$(yq r $VARS_YAML gcp.vm.network) \
    --metadata=ssh-keys="$(yq r $VARS_YAML gcp.vm.gcpPublicKey)" \
    --tags=$(yq r $VARS_YAML gcp.vm.tag) \
    --image=ubuntu-1804-bionic-v20210119a --image-project=ubuntu-os-cloud --machine-type=e2-medium
  export EXTERNAL_IP=$(gcloud beta compute --project=$(yq r $VARS_YAML gcp.env) instances describe $(yq r $VARS_YAML gcp.vm.name) --zone $(yq r $VARS_YAML gcp.vm.networkZone) | grep natIP | cut -d ":" -f 2 | tr -d ' ')  
  export INTERNAL_IP=$(gcloud beta compute --project=$(yq r $VARS_YAML gcp.env) instances describe $(yq r $VARS_YAML gcp.vm.name) --zone $(yq r $VARS_YAML gcp.vm.networkZone) | grep networkIP | cut -d ":" -f 2 | tr -d ' ')  
  sleep 30s #need to let ssh wake up
  # Prepare VM
  scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null scripts/mesh-expansion.sh $EXTERNAL_IP:~
  ssh $EXTERNAL_IP -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ./mesh-expansion.sh

  # Update YAMLs
  cp bookinfo/vm.yaml generated/bookinfo/
  yq write generated/bookinfo/vm.yaml -i "spec.address" $INTERNAL_IP
  yq write generated/bookinfo/vm.yaml -i 'metadata.annotations."sidecar-bootstrap.istio.io/proxy-instance-ip"' $INTERNAL_IP
  yq write generated/bookinfo/vm.yaml -i 'metadata.annotations."sidecar-bootstrap.istio.io/ssh-host"' $EXTERNAL_IP
  yq write generated/bookinfo/vm.yaml -i 'metadata.annotations."sidecar-bootstrap.istio.io/ssh-user"' $(yq r $VARS_YAML gcp.vm.sshUser)
else
  echo "Skipping GCP VM for Mesh Expansion"
fi
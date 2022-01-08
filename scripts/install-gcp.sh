#!/usr/bin/env bash
: ${VARS_YAML?"Need to set VARS_YAML environment variable"}

ENABLED=$(yq eval .gcp.skipImages)
if [ "$ENABLED" = "false" ];
then
  echo "Syncing bintray images"
  tctl install image-sync --username $(yq eval .tetrate.apiUser $VARS_YAML) \
    --apikey $(yq eval .tetrate.apiKey $VARS_YAML)  \
    --registry $(yq eval .tetrate.registry $VARS_YAML)
else
  echo "skipping image sync"
fi

ENABLED=$(yq eval .gcp.workload1.deploy $VARS_YAML)
if [ "$ENABLED" = "true" ];
then
  echo "Deploying GCP Workload Cluster 1..."
  gcloud container clusters create $(yq eval .gcp.workload1.clusterName $VARS_YAML) \
    --region $(yq eval .gcp.workload1.region $VARS_YAML) \
    --machine-type=$(yq eval .gcp.workload1.machineType $VARS_YAML) \
    --num-nodes=1 --min-nodes 0 --max-nodes 6 \
    --enable-autoscaling --enable-network-policy --release-channel=regular \
    --network "$(yq eval .gcp.workload1.network $VARS_YAML)" --subnetwork "$(yq eval .gcp.workload1.subNetwork $VARS_YAML)"
  gcloud container clusters get-credentials $(yq eval .gcp.workload1.clusterName $VARS_YAML) \
    --region $(yq eval .gcp.workload1.region $VARS_YAML) --project $(yq eval .gcp.env $VARS_YAML)
  
  source ./scripts/onboard-to-mp.sh \
    $(yq eval .gcp.workload1.clusterName $VARS_YAML) \
    $(yq eval .gcp.workload1.region $VARS_YAML)

  #Change Context back to workload cluster  
  gcloud container clusters get-credentials $(yq eval .gcp.workload1.clusterName $VARS_YAML) \
    --region $(yq eval .gcp.workload1.region $VARS_YAML) --project $(yq eval .gcp.env $VARS_YAML)
  source ./scripts/deploy-cp.sh \
    $(yq eval .gcp.workload1.clusterName $VARS_YAML) 
  source ./scripts/deploy-bookinfo.sh

else
  echo "Skipping GCP Workload Cluster 1"
fi

ENABLED=$(yq eval .gcp.workload2.deploy $VARS_YAML)
if [ "$ENABLED" = "true" ];
then
  echo "Deploying GCP Workload Cluster 2..."
  gcloud container clusters create $(yq eval .gcp.workload2.clusterName $VARS_YAML) \
    --region $(yq eval .gcp.workload2.region $VARS_YAML) \
    --machine-type=$(yq eval .gcp.workload2.machineType $VARS_YAML) \
    --num-nodes=1 --min-nodes 0 --max-nodes 6 \
    --enable-autoscaling --enable-network-policy --release-channel=regular \
    --network "$(yq eval .gcp.workload2.network $VARS_YAML)" --subnetwork "$(yq eval .gcp.workload2.subNetwork $VARS_YAML)"
  gcloud container clusters get-credentials $(yq eval .gcp.workload2.clusterName $VARS_YAML) \
    --region $(yq eval .gcp.workload2.region $VARS_YAML) --project $(yq eval .gcp.env $VARS_YAML)
  
  source ./scripts/onboard-to-mp.sh \
    $(yq eval .gcp.workload2.clusterName $VARS_YAML) \
    $(yq eval .gcp.workload2.region $VARS_YAML)

  #Change Context back to workload cluster  
  gcloud container clusters get-credentials $(yq eval .gcp.workload2.clusterName $VARS_YAML) \
    --region $(yq eval .gcp.workload2.region $VARS_YAML) --project $(yq eval .gcp.env $VARS_YAML)
  source ./scripts/deploy-cp.sh \
    $(yq eval .gcp.workload2.clusterName $VARS_YAML) 
  source ./scripts/deploy-bookinfo.sh
else
  echo "Skipping GCP Workload Cluster 2"
fi

ENABLED=$(yq eval .gcp.vm.deploy)
if [ "$ENABLED" = "true" ];
then
  echo "Deploying GCP VM for Mesh Expansion..."
  # Create VM
  gcloud beta compute --project=$(yq eval .gcp.env $VARS_YAML) instances create $(yq eval .gcp.vm.name $VARS_YAML) \
    --zone=$(yq eval .gcp.vm.networkZone $VARS_YAML) --subnet=$(yq eval .gcp.vm.network $VARS_YAML) \
    --metadata=ssh-keys="$(yq eval .gcp.vm.gcpPublicKey $VARS_YAML)" \
    --tags=$(yq eval .gcp.vm.tag $VARS_YAML) \
    --image=ubuntu-1804-bionic-v20210119a --image-project=ubuntu-os-cloud --machine-type=e2-medium
  export EXTERNAL_IP=$(gcloud beta compute --project=$(yq eval .gcp.env $VARS_YAML) instances describe $(yq eval .gcp.vm.name $VARS_YAML) --zone $(yq eval .gcp.vm.networkZone $VARS_YAML) | grep natIP | cut -d ":" -f 2 | tr -d ' ')  
  export INTERNAL_IP=$(gcloud beta compute --project=$(yq eval .gcp.env $VARS_YAML) instances describe $(yq eval .gcp.vm.name $VARS_YAML) --zone $(yq eval .gcp.vm.networkZone $VARS_YAML) | grep networkIP | cut -d ":" -f 2 | tr -d ' ')  
  sleep 30 #need to let ssh wake up
  # Prepare VM
  scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null scripts/mesh-expansion.sh $EXTERNAL_IP:~
  ssh $EXTERNAL_IP -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ./mesh-expansion.sh

  # Update YAMLs
  cp bookinfo/vm.yaml generated/bookinfo/
  export SSH_USER=$(yq eval .gcp.vm.sshUser $VARS_YAML)
  yq e -i '.spec.address=strenv(EXTERNAL_IP) |
        .metadata.annotations."sidecar-bootstrap.istio.io/proxy-instance-ip"=strenv(INTERNAL_IP) |
        .metadata.annotations."sidecar-bootstrap.istio.io/ssh-host"=strenv(EXTERNAL_IP) |
        .metadata.annotations."sidecar-bootstrap.istio.io/ssh-user"=strenv(SSH_USER)' \
          generated/bookinfo/vm.yaml

  yq write generated/bookinfo/vm.yaml -i "spec.address" $EXTERNAL_IP
  yq write generated/bookinfo/vm.yaml -i 'metadata.annotations."sidecar-bootstrap.istio.io/proxy-instance-ip"' $INTERNAL_IP
  yq write generated/bookinfo/vm.yaml -i 'metadata.annotations."sidecar-bootstrap.istio.io/ssh-host"' $EXTERNAL_IP
  yq write generated/bookinfo/vm.yaml -i 'metadata.annotations."sidecar-bootstrap.istio.io/ssh-user"' 
else
  echo "Skipping GCP VM for Mesh Expansion"
fi
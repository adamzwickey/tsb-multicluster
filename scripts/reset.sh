#!/usr/bin/env bash
: ${VARS_YAML?"Need to set VARS_YAML environment variable"}
echo config YAML:
cat $VARS_YAML

# Delete TSB Objects
tctl delete -f bookinfo/tsb.yaml

# VM
gcloud container clusters get-credentials $(yq r $VARS_YAML gcp.workload1.clusterName) \
   --region $(yq r $VARS_YAML gcp.workload1.region) --project $(yq r $VARS_YAML gcp.env)
kubectl delete -f generated/bookinfo/vm.yaml
gcloud beta compute --project=$(yq r $VARS_YAML gcp.env) instances delete $(yq r $VARS_YAML gcp.vm.name) \
  --zone=$(yq r $VARS_YAML gcp.vm.networkZone) --quiet
rm -rf ~/.ssh/known_hosts
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
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $EXTERNAL_IP ./mesh-expansion.sh

# Update YAMLs
cp bookinfo/vm.yaml generated/bookinfo/
yq write generated/bookinfo/vm.yaml -i "spec.address" $INTERNAL_IP
yq write generated/bookinfo/vm.yaml -i 'metadata.annotations."sidecar-bootstrap.istio.io/proxy-instance-ip"' $INTERNAL_IP
yq write generated/bookinfo/vm.yaml -i 'metadata.annotations."sidecar-bootstrap.istio.io/ssh-host"' $EXTERNAL_IP
yq write generated/bookinfo/vm.yaml -i 'metadata.annotations."sidecar-bootstrap.istio.io/ssh-user"' $(yq r $VARS_YAML gcp.vm.sshUser)


# Reset clusters with some baseline traffic

#T1
gcloud container clusters get-credentials $(yq r $VARS_YAML gcp.mgmt.clusterName) \
   --region $(yq r $VARS_YAML gcp.mgmt.region) --project $(yq r $VARS_YAML gcp.env)
source ./scripts/reset-t1.sh

ENABLED=$(yq r $VARS_YAML gcp.workload1.deploy)
if [ "$ENABLED" = "true" ];
then
   gcloud container clusters get-credentials $(yq r $VARS_YAML gcp.workload1.clusterName) \
      --region $(yq r $VARS_YAML gcp.workload1.region) --project $(yq r $VARS_YAML gcp.env)
   source ./scripts/reset-t2.sh   
else
  echo "Skipping GCP Workload Cluster 1"
fi

ENABLED=$(yq r $VARS_YAML gcp.workload2.deploy)
if [ "$ENABLED" = "true" ];
then
   gcloud container clusters get-credentials $(yq r $VARS_YAML gcp.workload2.clusterName) \
      --region $(yq r $VARS_YAML gcp.workload2.region) --project $(yq r $VARS_YAML gcp.env)
   source ./scripts/reset-t2.sh   
else
  echo "Skipping GCP Workload Cluster 2"
fi

ENABLED=$(yq r $VARS_YAML aws.workload1.deploy)
if [ "$ENABLED" = "true" ];
then
   aws eks --region $(yq r $VARS_YAML aws.workload1.region) update-kubeconfig \
    --name $(yq r $VARS_YAML aws.workload1.clusterName) 
   source ./scripts/reset-t2.sh  
else
  echo "Skipping AWS Workload Cluster 1"
fi

ENABLED=$(yq r $VARS_YAML aws.workload2.deploy)
if [ "$ENABLED" = "true" ];
then
   aws eks --region $(yq r $VARS_YAML aws.workload2.region) update-kubeconfig \
    --name $(yq r $VARS_YAML aws.workload2.clusterName) 
   source ./scripts/reset-t2.sh  
else
  echo "Skipping AWS Workload Cluster 2"
fi
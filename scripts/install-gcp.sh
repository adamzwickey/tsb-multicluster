#!/usr/bin/env bash
: ${VARS_YAML?"Need to set VARS_YAML environment variable"}

mkdir -p generated/$(yq r $VARS_YAML gcp.workload1.clusterName)
mkdir -p generated/$(yq r $VARS_YAML gcp.workload2.clusterName)
mkdir -p generated/bookinfo

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
  echo "Deploying GCP Workload Cluster 1"
  gcloud container clusters get-credentials $(yq r $VARS_YAML gcp.mgmt.clusterName) \
   --region $(yq r $VARS_YAML gcp.mgmt.region) --project $(yq r $VARS_YAML gcp.env)
  tctl install manifest cluster-operator \
    --registry $(yq r $VARS_YAML tetrate.registry) > generated/$(yq r $VARS_YAML gcp.workload1.clusterName)/cp-operator.yaml
  cp cluster.yaml generated/$(yq r $VARS_YAML gcp.workload1.clusterName)/
  yq write generated/$(yq r $VARS_YAML gcp.workload1.clusterName)/cluster.yaml -i "spec.locality.region" $(yq r $VARS_YAML gcp.workload1.region)
  yq write generated/$(yq r $VARS_YAML gcp.workload1.clusterName)/cluster.yaml -i "metadata.name" $(yq r $VARS_YAML gcp.workload1.clusterName)
  tctl apply -f generated/$(yq r $VARS_YAML gcp.workload1.clusterName)/cluster.yaml
  tctl install cluster-certs --cluster $(yq r $VARS_YAML gcp.workload1.clusterName) > generated/$(yq r $VARS_YAML gcp.workload1.clusterName)/cluster-certs.yaml
  tctl install manifest control-plane-secrets --cluster $(yq r $VARS_YAML gcp.workload1.clusterName) \
     --allow-defaults > generated/$(yq r $VARS_YAML gcp.workload1.clusterName)/cluster-secrets.yaml
  
  echo "Deploying workload cluster 1..."
  gcloud container clusters create $(yq r $VARS_YAML gcp.workload1.clusterName) \
    --region $(yq r $VARS_YAML gcp.workload1.region) \
    --machine-type=$(yq r $VARS_YAML gcp.workload1.machineType) \
    --num-nodes=1 --min-nodes 0 --max-nodes 6 \
    --enable-autoscaling --enable-network-policy --release-channel=regular \
    --network "$(yq r $VARS_YAML gcp.workload1.network)" --subnetwork "$(yq r $VARS_YAML gcp.workload1.subNetwork)"
  gcloud container clusters get-credentials $(yq r $VARS_YAML gcp.workload1.clusterName) \
    --region $(yq r $VARS_YAML gcp.workload1.region) --project $(yq r $VARS_YAML gcp.env)
  kubectl create ns istio-system
  kubectl create secret generic cacerts -n istio-system \
    --from-file=$(yq r $VARS_YAML k8s.istioCertDir)/ca-cert.pem \
    --from-file=$(yq r $VARS_YAML k8s.istioCertDir)/ca-key.pem \
    --from-file=$(yq r $VARS_YAML k8s.istioCertDir)/root-cert.pem \
    --from-file=$(yq r $VARS_YAML k8s.istioCertDir)/cert-chain.pem
  kubectl apply -f generated/$(yq r $VARS_YAML gcp.workload1.clusterName)/cp-operator.yaml
  kubectl apply -f generated/$(yq r $VARS_YAML gcp.workload1.clusterName)/cluster-certs.yaml
  kubectl apply -f generated/$(yq r $VARS_YAML gcp.workload1.clusterName)/cluster-secrets.yaml
  while kubectl get po -n istio-system -l name=tsb-operator | grep Running | wc -l | grep 1 ; [ $? -ne 0 ]; do
      echo TSB Operator is not yet ready
      sleep 5s
  done
  sleep 30 # Dig into why this is needed
  cp control-plane.yaml generated/$(yq r $VARS_YAML gcp.workload1.clusterName)/
  yq write generated/$(yq r $VARS_YAML gcp.workload1.clusterName)/control-plane.yaml -i "spec.hub" $(yq r $VARS_YAML tetrate.registry)
  yq write generated/$(yq r $VARS_YAML gcp.workload1.clusterName)/control-plane.yaml -i "spec.telemetryStore.elastic.host" $(yq r $VARS_YAML gcp.mgmt.fqdn)
  yq write generated/$(yq r $VARS_YAML gcp.workload1.clusterName)/control-plane.yaml -i "spec.managementPlane.host" $(yq r $VARS_YAML gcp.mgmt.fqdn)
  yq write generated/$(yq r $VARS_YAML gcp.workload1.clusterName)/control-plane.yaml -i "spec.managementPlane.clusterName" $(yq r $VARS_YAML gcp.workload1.clusterName)
  kubectl apply -f generated/$(yq r $VARS_YAML gcp.workload1.clusterName)/control-plane.yaml
  #Edge Pod is the last thing to start
  while kubectl get po -n istio-system -l app=edge | grep Running | wc -l | grep 1 ; [ $? -ne 0 ]; do
      echo Istio control plane is not yet ready
      sleep 5s
  done
  kubectl patch ControlPlane controlplane -n istio-system --patch '{"spec":{"meshExpansion":{}}}' --type merge

  #Bookinfo
  kubectl create ns bookinfo
  kubectl apply -n bookinfo -f bookinfo/bookinfo.yaml
  kubectl apply -n bookinfo -f bookinfo/cluster-ingress-gw.yaml
  kubectl -n bookinfo create secret tls bookinfo-certs \
    --key $(yq r $VARS_YAML k8s.bookinfoCertDir)/privkey.pem \
    --cert $(yq r $VARS_YAML k8s.bookinfoCertDir)/fullchain.pem
  while kubectl get po -n bookinfo | grep Running | wc -l | grep 7 ; [ $? -ne 0 ]; do
      echo Bookinfo is not yet ready
      sleep 5s
  done
  while kubectl get service tsb-gateway-bookinfo -n bookinfo | grep pending | wc -l | grep 0 ; [ $? -ne 0 ]; do
      echo Gateway IP not assigned
      sleep 5s
  done
  export GATEWAY_IP=$(kubectl get service tsb-gateway-bookinfo -n bookinfo -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
  kubectl apply -f bookinfo/tmp.yaml
  for i in {1..50}
  do
     curl -vv http://$GATEWAY_IP/productpage\?u=normal
  done
  kubectl delete -f bookinfo/tmp.yaml
  kubectl apply -n bookinfo -f bookinfo/bookinfo-multi.yaml
else
  echo "Skipping GCP Workload Cluster 1"
fi

ENABLED=$(yq r $VARS_YAML gcp.workload2.deploy)
if [ "$ENABLED" = "true" ];
then
  echo "Deploying GCP Workload Cluster 2"
  gcloud container clusters get-credentials $(yq r $VARS_YAML gcp.mgmt.clusterName) \
   --region $(yq r $VARS_YAML gcp.mgmt.region) --project $(yq r $VARS_YAML gcp.env)
  tctl install manifest cluster-operator \
    --registry $(yq r $VARS_YAML tetrate.registry) > generated/$(yq r $VARS_YAML gcp.workload2.clusterName)/cp-operator.yaml 
  cp cluster.yaml generated/$(yq r $VARS_YAML gcp.workload2.clusterName)/
  yq write generated/$(yq r $VARS_YAML gcp.workload2.clusterName)/cluster.yaml -i "spec.locality.region" $(yq r $VARS_YAML gcp.workload2.region)
  yq write generated/$(yq r $VARS_YAML gcp.workload2.clusterName)/cluster.yaml -i "metadata.name" $(yq r $VARS_YAML gcp.workload2.clusterName)
  tctl apply -f generated/$(yq r $VARS_YAML gcp.workload2.clusterName)/cluster.yaml
  tctl install cluster-certs --cluster $(yq r $VARS_YAML gcp.workload2.clusterName) > generated/$(yq r $VARS_YAML gcp.workload2.clusterName)/cluster-certs.yaml
  tctl install manifest control-plane-secrets --cluster $(yq r $VARS_YAML gcp.workload2.clusterName) \
     --allow-defaults > generated/$(yq r $VARS_YAML gcp.workload2.clusterName)/cluster-secrets.yaml

  echo "Deploying workload cluster 2..."
  gcloud container clusters create $(yq r $VARS_YAML gcp.workload2.clusterName) \
    --region $(yq r $VARS_YAML gcp.workload2.region) \
    --machine-type=$(yq r $VARS_YAML gcp.workload2.machineType) \
    --num-nodes=1 --min-nodes 0 --max-nodes 6 \
    --enable-autoscaling --enable-network-policy --release-channel=regular \
    --network "$(yq r $VARS_YAML gcp.workload2.network)" --subnetwork "$(yq r $VARS_YAML gcp.workload2.subNetwork)"
  gcloud container clusters get-credentials $(yq r $VARS_YAML gcp.workload2.clusterName) \
    --region $(yq r $VARS_YAML gcp.workload2.region) --project $(yq r $VARS_YAML gcp.env)
  kubectl create ns istio-system
  kubectl create secret generic cacerts -n istio-system \
    --from-file=$(yq r $VARS_YAML k8s.istioCertDir)/ca-cert.pem \
    --from-file=$(yq r $VARS_YAML k8s.istioCertDir)/ca-key.pem \
    --from-file=$(yq r $VARS_YAML k8s.istioCertDir)/root-cert.pem \
    --from-file=$(yq r $VARS_YAML k8s.istioCertDir)/cert-chain.pem
  kubectl apply -f generated/$(yq r $VARS_YAML gcp.workload2.clusterName)/cp-operator.yaml
  kubectl apply -f generated/$(yq r $VARS_YAML gcp.workload2.clusterName)/cluster-certs.yaml
  kubectl apply -f generated/$(yq r $VARS_YAML gcp.workload2.clusterName)/cluster-secrets.yaml
  while kubectl get po -n istio-system -l name=tsb-operator | grep Running | wc -l | grep 1 ; [ $? -ne 0 ]; do
      echo TSB Operator is not yet ready
      sleep 5s
  done
  sleep 30 # Dig into why this is needed
  cp control-plane.yaml generated/$(yq r $VARS_YAML gcp.workload2.clusterName)/
  yq write generated/$(yq r $VARS_YAML gcp.workload2.clusterName)/control-plane.yaml -i "spec.hub" $(yq r $VARS_YAML tetrate.registry)
  yq write generated/$(yq r $VARS_YAML gcp.workload2.clusterName)/control-plane.yaml -i "spec.telemetryStore.elastic.host" $(yq r $VARS_YAML gcp.mgmt.fqdn)
  yq write generated/$(yq r $VARS_YAML gcp.workload2.clusterName)/control-plane.yaml -i "spec.managementPlane.host" $(yq r $VARS_YAML gcp.mgmt.fqdn)
  yq write generated/$(yq r $VARS_YAML gcp.workload2.clusterName)/control-plane.yaml -i "spec.managementPlane.clusterName" $(yq r $VARS_YAML gcp.workload2.clusterName)
  kubectl apply -f generated/$(yq r $VARS_YAML gcp.workload2.clusterName)/control-plane.yaml
  #Edge Pod is the last thing to start
  while kubectl get po -n istio-system -l app=edge | grep Running | wc -l | grep 1 ; [ $? -ne 0 ]; do
      echo Istio control plane is not yet ready
      sleep 5s
  done
  kubectl patch ControlPlane controlplane -n istio-system --patch '{"spec":{"meshExpansion":{}}}' --type merge

  #Bookinfo
  kubectl create ns bookinfo
  kubectl apply -n bookinfo -f bookinfo/bookinfo.yaml
  kubectl apply -n bookinfo -f bookinfo/cluster-ingress-gw.yaml
  kubectl -n bookinfo create secret tls bookinfo-certs \
    --key $(yq r $VARS_YAML k8s.bookinfoCertDir)/privkey.pem \
    --cert $(yq r $VARS_YAML k8s.bookinfoCertDir)/fullchain.pem
  while kubectl get po -n bookinfo | grep Running | wc -l | grep 7 ; [ $? -ne 0 ]; do
      echo Bookinfo is not yet ready
      sleep 5s
  done
  while kubectl get service tsb-gateway-bookinfo -n bookinfo | grep pending | wc -l | grep 0 ; [ $? -ne 0 ]; do
      echo Gateway IP not assigned
      sleep 5s
  done
  export GATEWAY_IP=$(kubectl get service tsb-gateway-bookinfo -n bookinfo -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
  kubectl apply -f bookinfo/tmp.yaml
  for i in {1..50}
  do
     curl -vv http://$GATEWAY_IP/productpage\?u=normal
  done
  kubectl delete -f bookinfo/tmp.yaml
  kubectl apply -n bookinfo -f bookinfo/bookinfo-multi.yaml
else
  echo "Skipping GCP Workload Cluster 2"
fi

# Prepare VM Expansion
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
#!/usr/bin/env bash
: ${VARS_YAML?"Need to set VARS_YAML environment variable"}

ENABLED=$(yq eval .gcp.skipImages $VARS_YAML)
if [ "$ENABLED" = "false" ];
then
  echo "Syncing bintray images"
  tctl install image-sync --username $(yq eval .tetrate.apiUser $VARS_YAML) \
    --apikey $(yq eval .tetrate.apiKey $VARS_YAML)  \
    --registry $(yq eval .tetrate.registry $VARS_YAML)
else
  echo "skipping image sync"
fi

echo "Deploying mgmt cluster..."
gcloud container clusters create $(yq eval .gcp.mgmt.clusterName $VARS_YAML) \
    --region $(yq eval .gcp.mgmt.region $VARS_YAML) \
    --machine-type=$(yq eval .gcp.mgmt.machineType $VARS_YAML) \
    --num-nodes=1 --min-nodes 0 --max-nodes 6 \
    --enable-autoscaling --enable-network-policy --release-channel "regular" \
    --network "$(yq eval .gcp.mgmt.network $VARS_YAML)" --subnetwork "$(yq eval .gcp.mgmt.subNetwork $VARS_YAML)"
gcloud container clusters get-credentials $(yq eval .gcp.mgmt.clusterName $VARS_YAML) \
   --region $(yq eval .gcp.mgmt.region $VARS_YAML) --project $(yq eval .gcp.env $VARS_YAML)

echo "Installing TSB mgmt cluster..."
mkdir -p generated/$(yq eval .gcp.mgmt.clusterName $VARS_YAML)

kubectl apply -f https://github.com/jetstack/cert-manager/releases/download/v1.6.1/cert-manager.yaml
kubectl create secret generic clouddns-dns01-solver-svc-acct -n cert-manager \
    --from-file=$(yq eval .gcp.accountJsonKey $VARS_YAML)
while kubectl get po -n cert-manager | grep Running | wc -l | grep 3 ; [ $? -ne 0 ]; do
    echo Cert Manager is not yet ready
    sleep 5
done

kubectl create ns tsb
cp cluster-issuer.yaml generated/$(yq eval .gcp.mgmt.clusterName $VARS_YAML)/cluster-issuer.yaml
cp cluster-cert.yaml generated/$(yq eval .gcp.mgmt.clusterName $VARS_YAML)/cluster-cert.yaml
export EMAIL=$(yq eval .gcp.acme.email $VARS_YAML)
export PROJECT=$(yq eval .gcp.env $VARS_YAML)
export ZONE=$(yq eval .gcp.acme.dnsZone $VARS_YAML)
export DNS=$(yq eval .gcp.mgmt.fqdn $VARS_YAML)
yq e -i '.spec.acme.email=strenv(EMAIL) |
  .spec.acme.solvers[0].dns01.cloudDNS.project=strenv(PROJECT) |
  .spec.acme.solvers[0].selector.dnsZones[0]=strenv(ZONE)' generated/$(yq eval .gcp.mgmt.clusterName $VARS_YAML)/cluster-issuer.yaml
yq e -i '.spec.dnsNames[0]=strenv(DNS)' generated/$(yq eval .gcp.mgmt.clusterName $VARS_YAML)/cluster-cert.yaml
kubectl apply -f generated/$(yq eval .gcp.mgmt.clusterName $VARS_YAML)/cluster-issuer.yaml 
kubectl apply -f generated/$(yq eval .gcp.mgmt.clusterName $VARS_YAML)/cluster-cert.yaml 
while kubectl get certificates.cert-manager.io -n tsb tsb-certs | grep True; [ $? -ne 0 ]; do
	echo TSB Certificate is not yet ready
	sleep 5
done

tctl install manifest management-plane-operator --registry $(yq eval .tetrate.registry $VARS_YAML) > generated/$(yq eval .gcp.mgmt.clusterName $VARS_YAML)/mp-operator.yaml
kubectl apply -f generated/$(yq eval .gcp.mgmt.clusterName $VARS_YAML)/mp-operator.yaml
while kubectl get po -n tsb -l name=tsb-operator | grep Running | wc -l | grep 1 ; [ $? -ne 0 ]; do
    echo TSB Operator is not yet ready
    sleep 5
done

source ./scripts/deploy-keycloak.sh

tctl install manifest management-plane-secrets \
    --elastic-password tsb-elastic-password --elastic-username tsb \
    --oidc-client-secret TOPSECRET \
    --postgres-password $(yq eval .gcp.mgmt.postgres.password $VARS_YAML) \
    --postgres-username $(yq eval .gcp.mgmt.postgres.username $VARS_YAML) \
    --tsb-admin-password $(yq eval .gcp.mgmt.password $VARS_YAML)  --allow-defaults \
    --xcp-certs > generated/$(yq eval .gcp.mgmt.clusterName $VARS_YAML)/mp-secrets.yaml
#We're not going to use tsb cert since we already have one we're generating from cert-manager
sed -i '' s/tsb-certs/tsb-cert-old/ generated/$(yq eval .gcp.mgmt.clusterName $VARS_YAML)/mp-secrets.yaml 
kubectl apply -f generated/$(yq eval .gcp.mgmt.clusterName $VARS_YAML)/mp-secrets.yaml 

echo "Deploying mgmt plane"
sleep 10 # Dig into why this is needed
cp mgmt-mp.yaml generated/$(yq eval .gcp.mgmt.clusterName $VARS_YAML)/mp.yaml
export REGISTRY=$(yq eval .tetrate.registry $VARS_YAML)
export POSTGRES=$(yq eval .gcp.mgmt.postgres.host $VARS_YAML)
yq e -i '.spec.acme.email=strenv(EMAIL) |
  .spec.hub=strenv(REGISTRY) |
  .spec.dataStore.postgres.host=strenv(POSTGRES)' generated/$(yq eval .gcp.mgmt.clusterName $VARS_YAML)/mp.yaml
kubectl apply -f generated/$(yq eval .gcp.mgmt.clusterName $VARS_YAML)/mp.yaml
#Central is last component to start up
while kubectl get po -n tsb -l app=central | grep Running | wc -l | grep 1 ; [ $? -ne 0 ]; do
    echo TSB mgmt plane is not yet ready
    sleep 5
done
kubectl create job -n tsb teamsync-bootstrap --from=cronjob/teamsync
while kubectl get svc envoy -n tsb | grep pending | wc -l | grep 0 ; [ $? -ne 0 ]; do
    echo TSB IP not assigned
    sleep 5
done

echo "Configuring DNS for TSB mgmt cluster..."
export TSB_IP_OLD=$(nslookup $(yq eval .gcp.mgmt.fqdn $VARS_YAML) | grep 'Address:' | tail -n1 | awk '{print $2}')
export TSB_IP=$(kubectl get svc -n tsb envoy -o json --output jsonpath='{.status.loadBalancer.ingress[0].ip}')  
gcloud beta dns --project=$(yq eval .gcp.env $VARS_YAML) record-sets transaction start --zone=$(yq eval .gcp.acme.dnsZoneId $VARS_YAML)
gcloud beta dns --project=$(yq eval .gcp.env $VARS_YAML) record-sets transaction remove $TSB_IP_OLD --name=$(yq eval .gcp.mgmt.fqdn $VARS_YAML). --ttl=300 --type=A --zone=$(yq eval .gcp.acme.dnsZoneId $VARS_YAML)
gcloud beta dns --project=$(yq eval .gcp.env $VARS_YAML) record-sets transaction add $TSB_IP --name=$(yq eval .gcp.mgmt.fqdn $VARS_YAML). --ttl=300 --type=A --zone=$(yq eval .gcp.acme.dnsZoneId $VARS_YAML)
gcloud beta dns --project=$(yq eval .gcp.env $VARS_YAML) record-sets transaction execute --zone=$(yq eval .gcp.acme.dnsZoneId $VARS_YAML)
echo “Old tsb ip: $TSB_IP_OLD“
echo “New tsb ip: $TSB_IP“

while nslookup $(yq eval .gcp.mgmt.fqdn $VARS_YAML) | grep $TSB_IP ; [ $? -ne 0 ]; do
	echo TSB DNS is not yet propagated
	sleep 5
done

echo "Logging into TSB mgmt cluster..."
tctl config clusters set default --bridge-address $(yq eval .gcp.mgmt.fqdn $VARS_YAML):443
tctl login --org tetrate --tenant tetrate --username admin --password $(yq eval .gcp.mgmt.password $VARS_YAML)
sleep 3
tctl get Clusters

tctl install manifest cluster-operator \
    --registry $(yq eval .tetrate.registry $VARS_YAML) > generated/$(yq eval .gcp.mgmt.clusterName $VARS_YAML)/cp-operator.yaml
kubectl create ns istio-system

kubectl create secret generic cacerts -n istio-system \
  --from-file=$(yq eval .k8s.istioCertDir $VARS_YAML)/ca-cert.pem \
  --from-file=$(yq eval .k8s.istioCertDir $VARS_YAML)/ca-key.pem \
  --from-file=$(yq eval .k8s.istioCertDir $VARS_YAML)/root-cert.pem \
  --from-file=$(yq eval .k8s.istioCertDir $VARS_YAML)/cert-chain.pem
kubectl apply -f generated/$(yq eval .gcp.mgmt.clusterName $VARS_YAML)/cp-operator.yaml

cp mgmt-cluster.yaml generated/$(yq eval .gcp.mgmt.clusterName $VARS_YAML)/mgmt-cluster.yaml
export NAME=$(yq eval .gcp.mgmt.clusterName $VARS_YAML)
yq e -i '.metadata.name=strenv(NAME)' generated/$(yq eval .gcp.mgmt.clusterName $VARS_YAML)/mgmt-cluster.yaml
tctl apply -f generated/$(yq eval .gcp.mgmt.clusterName $VARS_YAML)/mgmt-cluster.yaml

tctl install cluster-certs --cluster $(yq eval .gcp.mgmt.clusterName $VARS_YAML) > generated/$(yq eval .gcp.mgmt.clusterName $VARS_YAML)/mgmt-cluster-certs.yaml
tctl install manifest control-plane-secrets --cluster $(yq eval .gcp.mgmt.clusterName $VARS_YAML) \
   --allow-defaults > generated/$(yq eval .gcp.mgmt.clusterName $VARS_YAML)/mgmt-cluster-secrets.yaml
kubectl apply -f generated/$(yq eval .gcp.mgmt.clusterName $VARS_YAML)/mgmt-cluster-certs.yaml
kubectl apply -f generated/$(yq eval .gcp.mgmt.clusterName $VARS_YAML)/mgmt-cluster-secrets.yaml
sleep 30 # Dig into why this is needed
cp mgmt-cp.yaml generated/$(yq eval .gcp.mgmt.clusterName $VARS_YAML)/mgmt-cp.yaml
export REGISTRY=$(yq eval .tetrate.registry $VARS_YAML)
export MP=$(yq eval .gcp.mgmt.fqdn $VARS_YAML)
export CLUSTER_NAME=$(yq eval .gcp.mgmt.clusterName $VARS_YAML)
yq e -i '.spec.hub=strenv(REGISTRY) |
        .spec.telemetryStore.elastic.host=strenv(MP) |
        .spec.managementPlane.host=strenv(MP) |
        .spec.managementPlane.clusterName=strenv(CLUSTER_NAME)' generated/$(yq eval .gcp.mgmt.clusterName $VARS_YAML)/mgmt-cp.yaml
kubectl apply -f generated/$(yq eval .gcp.mgmt.clusterName $VARS_YAML)/mgmt-cp.yaml
kubectl patch ControlPlane controlplane -n istio-system --patch '{"spec":{"meshExpansion":{}}}' --type merge
#Edge is last component to start
while kubectl get po -n istio-system -l app=edge | grep Running | wc -l | grep 1 ; [ $? -ne 0 ]; do
    echo Istio control plane is not yet ready
    sleep 5
done

#Setup TSB Objects
tctl apply -f bookinfo/workspace.yaml
mkdir -p generated/bookinfo/
cp bookinfo/tsb.yaml generated/bookinfo/tsb.yaml
export BOOKINFO_HOST=$(yq eval .bookinfo.fqdn $VARS_YAML)
yq e -i '.spec.http[0].hostname=strenv(BOOKINFO_HOST) |
        .spec.externalServers[0].hostname=strenv(BOOKINFO_HOST)' generated/bookinfo/tsb.yaml
tctl apply -f generated/bookinfo/tsb.yaml

#Bookinfo
kubectl create ns t1
kubectl create secret tls bookinfo-certs -n t1 \
    --key $(yq eval .k8s.bookinfoCertDir $VARS_YAML)/privkey.pem \
    --cert $(yq eval .k8s.bookinfoCertDir $VARS_YAML)/fullchain.pem
kubectl apply -f bookinfo/cluster-t1.yaml
sleep 5
while kubectl get svc tsb-tier1 -n t1 | grep pending | wc -l | grep 0 ; [ $? -ne 0 ]; do
    echo Tier 1 Gateway IP not assigned
    sleep 5
done
export T1_GATEWAY_IP=$(kubectl get service tsb-tier1 -n t1 -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
export T1_GATEWAY_IP_OLD=$(nslookup $(yq eval .bookinfo.fqdn $VARS_YAML) | grep 'Address:' | tail -n1 | awk '{print $2}')
gcloud beta dns --project=$(yq eval .gcp.env $VARS_YAML) record-sets transaction start --zone=$(yq eval .gcp.acme.dnsZoneId $VARS_YAML)
gcloud beta dns --project=$(yq eval .gcp.env $VARS_YAML) record-sets transaction remove $T1_GATEWAY_IP_OLD --name=$(yq eval .bookinfo.fqdn $VARS_YAML). --ttl=300 --type=A --zone=$(yq eval .gcp.acme.dnsZoneId $VARS_YAML)
gcloud beta dns --project=$(yq eval .gcp.env $VARS_YAML) record-sets transaction add $T1_GATEWAY_IP --name=$(yq eval .bookinfo.fqdn $VARS_YAML). --ttl=300 --type=A --zone=$(yq eval .gcp.acme.dnsZoneId $VARS_YAML)
gcloud beta dns --project=$(yq eval .gcp.env $VARS_YAML) record-sets transaction execute --zone=$(yq eval .gcp.acme.dnsZoneId $VARS_YAML)
echo “Old Tier 1 ip: $T1_GATEWAY_IP_OLD
echo “New Tier 1 ip: $T1_GATEWAY_IP

kubectl apply -f bookinfo/tmp1.yaml
for i in {1..50}
do
   curl -vv http://$T1_GATEWAY_IP
done
kubectl delete -f bookinfo/tmp1.yaml

while nslookup $(yq eval .bookinfo.fqdn $VARS_YAML) | grep $T1_GATEWAY_IP ; [ $? -ne 0 ]; do
	echo Tier1 Gateway DNS is not yet propagated
	sleep 5
done
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

echo "Deploying mgmt cluster..."
gcloud container clusters create $(yq r $VARS_YAML gcp.mgmt.clusterName) \
    --region $(yq r $VARS_YAML gcp.mgmt.region) \
    --machine-type=$(yq r $VARS_YAML gcp.mgmt.machineType) \
    --num-nodes=1 --min-nodes 0 --max-nodes 6 \
    --enable-autoscaling --enable-network-policy --release-channel=regular \
    --network "$(yq r $VARS_YAML gcp.mgmt.network)" --subnetwork "$(yq r $VARS_YAML gcp.mgmt.subNetwork)"
gcloud container clusters get-credentials $(yq r $VARS_YAML gcp.mgmt.clusterName) \
   --region $(yq r $VARS_YAML gcp.mgmt.region) --project $(yq r $VARS_YAML gcp.env)

echo "Installing TSB mgmt cluster..."
mkdir -p generated/$(yq r $VARS_YAML gcp.mgmt.clusterName)

kubectl apply -f https://github.com/jetstack/cert-manager/releases/download/v1.3.1/cert-manager.yaml
kubectl create secret generic clouddns-dns01-solver-svc-acct -n cert-manager \
    --from-file=$(yq r $VARS_YAML gcp.accountJsonKey)
while kubectl get po -n cert-manager | grep Running | wc -l | grep 3 ; [ $? -ne 0 ]; do
    echo Cert Manager is not yet ready
    sleep 5s
done

kubectl create ns tsb
cp cluster-issuer.yaml generated/$(yq r $VARS_YAML gcp.mgmt.clusterName)/cluster-issuer.yaml
yq write generated/$(yq r $VARS_YAML gcp.mgmt.clusterName)/cluster-issuer.yaml -i "spec.acme.email" $(yq r $VARS_YAML gcp.acme.email)
yq write generated/$(yq r $VARS_YAML gcp.mgmt.clusterName)/cluster-issuer.yaml -i "spec.acme.solvers[0].dns01.cloudDNS.project" $(yq r $VARS_YAML gcp.env)
yq write generated/$(yq r $VARS_YAML gcp.mgmt.clusterName)/cluster-issuer.yaml -i "spec.acme.solvers[0].selector.dnsZones[0]" $(yq r $VARS_YAML gcp.acme.dnsZone)
yq write generated/$(yq r $VARS_YAML gcp.mgmt.clusterName)/cluster-issuer.yaml -d1 -i "spec.dnsNames[0]" $(yq r $VARS_YAML gcp.mgmt.fqdn)
kubectl apply -f generated/$(yq r $VARS_YAML gcp.mgmt.clusterName)/cluster-issuer.yaml 
while kubectl get certificates.cert-manager.io -n tsb tsb-certs | grep True; [ $? -ne 0 ]; do
	echo TSB Certificate is not yet ready
	sleep 5s
done

tctl install manifest management-plane-operator --registry $(yq r $VARS_YAML tetrate.registry) > generated/$(yq r $VARS_YAML gcp.mgmt.clusterName)/mp-operator.yaml
kubectl apply -f generated/$(yq r $VARS_YAML gcp.mgmt.clusterName)/mp-operator.yaml
while kubectl get po -n tsb -l name=tsb-operator | grep Running | wc -l | grep 1 ; [ $? -ne 0 ]; do
    echo TSB Operator is not yet ready
    sleep 5s
done

tctl install manifest management-plane-secrets \
    --elastic-password tsb-elastic-password --elastic-username tsb \
    --ldap-bind-dn cn=admin,dc=tetrate,dc=io --ldap-bind-password admin \
    --postgres-password $(yq r $VARS_YAML gcp.mgmt.postgres.password) \
    --postgres-username $(yq r $VARS_YAML gcp.mgmt.postgres.username) \
    --tsb-admin-password $(yq r $VARS_YAML gcp.mgmt.password) --tsb-server-certificate aaa --tsb-server-key bbb \
    --xcp-certs > generated/$(yq r $VARS_YAML gcp.mgmt.clusterName)/mp-secrets.yaml
#We're not going to use tsb cert since we already have one we're generating from cert-manager
sed -i '' s/tsb-certs/tsb-cert-old/ generated/$(yq r $VARS_YAML gcp.mgmt.clusterName)/mp-secrets.yaml 
kubectl apply -f generated/$(yq r $VARS_YAML gcp.mgmt.clusterName)/mp-secrets.yaml 

echo "Deploying mgmt plane"
sleep 10 # Dig into why this is needed
cp mgmt-mp.yaml generated/$(yq r $VARS_YAML gcp.mgmt.clusterName)/mp.yaml
yq write generated/$(yq r $VARS_YAML gcp.mgmt.clusterName)/mp.yaml -i "spec.hub" $(yq r $VARS_YAML tetrate.registry)
yq write generated/$(yq r $VARS_YAML gcp.mgmt.clusterName)/mp.yaml -i "spec.dataStore.postgres.host" $(yq r $VARS_YAML gcp.mgmt.postgres.host)
kubectl apply -f generated/$(yq r $VARS_YAML gcp.mgmt.clusterName)/mp.yaml
#Central is last component to start up
while kubectl get po -n tsb -l app=central | grep Running | wc -l | grep 1 ; [ $? -ne 0 ]; do
    echo TSB mgmt plane is not yet ready
    sleep 5s
done
kubectl create job -n tsb teamsync-bootstrap --from=cronjob/teamsync

echo "Configuring DNS for TSB mgmt cluster..."
export TSB_IP_OLD=$(nslookup $(yq r $VARS_YAML gcp.mgmt.fqdn) | grep 'Address:' | tail -n1 | awk '{print $2}')
export TSB_IP=$(kubectl get svc -n tsb envoy -o json --output jsonpath='{.status.loadBalancer.ingress[0].ip}')  
gcloud beta dns --project=$(yq r $VARS_YAML gcp.env) record-sets transaction start --zone=$(yq r $VARS_YAML gcp.acme.dnsZoneId)
gcloud beta dns --project=$(yq r $VARS_YAML gcp.env) record-sets transaction remove $TSB_IP_OLD --name=$(yq r $VARS_YAML gcp.mgmt.fqdn). --ttl=300 --type=A --zone=$(yq r $VARS_YAML gcp.acme.dnsZoneId)
gcloud beta dns --project=$(yq r $VARS_YAML gcp.env) record-sets transaction add $TSB_IP --name=$(yq r $VARS_YAML gcp.mgmt.fqdn). --ttl=300 --type=A --zone=$(yq r $VARS_YAML gcp.acme.dnsZoneId)
gcloud beta dns --project=$(yq r $VARS_YAML gcp.env) record-sets transaction execute --zone=$(yq r $VARS_YAML gcp.acme.dnsZoneId)
echo “Old tsb ip: $TSB_IP_OLD“
echo “New tsb ip: $TSB_IP“

while nslookup $(yq r $VARS_YAML gcp.mgmt.fqdn) | grep $TSB_IP ; [ $? -ne 0 ]; do
	echo TSB DNS is not yet propagated
	sleep 5s
done

echo "Logging into TSB mgmt cluster..."
tctl config clusters set default --bridge-address $(yq r $VARS_YAML gcp.mgmt.fqdn):443
tctl login --org tetrate --tenant tetrate --username admin --password $(yq r $VARS_YAML gcp.mgmt.password)
sleep 3
tctl get Clusters

tctl install manifest cluster-operator \
    --registry $(yq r $VARS_YAML tetrate.registry) > generated/$(yq r $VARS_YAML gcp.mgmt.clusterName)/cp-operator.yaml
kubectl create ns istio-system

kubectl create secret generic cacerts -n istio-system \
  --from-file=$(yq r $VARS_YAML k8s.istioCertDir)/ca-cert.pem \
  --from-file=$(yq r $VARS_YAML k8s.istioCertDir)/ca-key.pem \
  --from-file=$(yq r $VARS_YAML k8s.istioCertDir)/root-cert.pem \
  --from-file=$(yq r $VARS_YAML k8s.istioCertDir)/cert-chain.pem
kubectl apply -f generated/$(yq r $VARS_YAML gcp.mgmt.clusterName)/cp-operator.yaml
cp mgmt-cluster.yaml generated/$(yq r $VARS_YAML gcp.mgmt.clusterName)/mgmt-cluster.yaml
yq write generated/$(yq r $VARS_YAML gcp.mgmt.clusterName)/mgmt-cluster.yaml -i "metadata.name" $(yq r $VARS_YAML gcp.mgmt.clusterName)
tctl apply -f generated/$(yq r $VARS_YAML gcp.mgmt.clusterName)/mgmt-cluster.yaml
tctl install cluster-certs --cluster $(yq r $VARS_YAML gcp.mgmt.clusterName) > generated/$(yq r $VARS_YAML gcp.mgmt.clusterName)/mgmt-cluster-certs.yaml
tctl install manifest control-plane-secrets --cluster $(yq r $VARS_YAML gcp.mgmt.clusterName) \
   --allow-defaults > generated/$(yq r $VARS_YAML gcp.mgmt.clusterName)/mgmt-cluster-secrets.yaml
kubectl apply -f generated/$(yq r $VARS_YAML gcp.mgmt.clusterName)/mgmt-cluster-certs.yaml
kubectl apply -f generated/$(yq r $VARS_YAML gcp.mgmt.clusterName)/mgmt-cluster-secrets.yaml
sleep 30 # Dig into why this is needed
cp mgmt-cp.yaml generated/$(yq r $VARS_YAML gcp.mgmt.clusterName)/mgmt-cp.yaml
yq write generated/$(yq r $VARS_YAML gcp.mgmt.clusterName)/mgmt-cp.yaml -i "spec.hub" $(yq r $VARS_YAML tetrate.registry)
yq write generated/$(yq r $VARS_YAML gcp.mgmt.clusterName)/mgmt-cp.yaml -i "spec.telemetryStore.elastic.host" $(yq r $VARS_YAML gcp.mgmt.fqdn)
yq write generated/$(yq r $VARS_YAML gcp.mgmt.clusterName)/mgmt-cp.yaml -i "spec.managementPlane.host" $(yq r $VARS_YAML gcp.mgmt.fqdn)
yq write generated/$(yq r $VARS_YAML gcp.mgmt.clusterName)/mgmt-cp.yaml -i "spec.managementPlane.clusterName" $(yq r $VARS_YAML gcp.mgmt.clusterName)
kubectl apply -f generated/$(yq r $VARS_YAML gcp.mgmt.clusterName)/mgmt-cp.yaml
kubectl patch ControlPlane controlplane -n istio-system --patch '{"spec":{"meshExpansion":{}}}' --type merge
#Edge is last component to start
while kubectl get po -n istio-system -l app=edge | grep Running | wc -l | grep 1 ; [ $? -ne 0 ]; do
    echo Istio control plane is not yet ready
    sleep 5s
done

#Setup TSB Objects
tctl apply -f bookinfo/workspace.yaml
cp bookinfo/tsb.yaml generated/bookinfo/tsb.yaml
yq write generated/bookinfo/tsb.yaml -d2 -i "spec.http[0].hostname" $(yq r $VARS_YAML bookinfo.fqdn)
yq write generated/bookinfo/tsb.yaml -d3 -i "spec.externalServers[0].hostname" $(yq r $VARS_YAML bookinfo.fqdn)

#Bookinfo
kubectl create ns t1
kubectl create secret tls bookinfo-certs -n t1 \
    --key $(yq r $VARS_YAML k8s.bookinfoCertDir)/privkey.pem \
    --cert $(yq r $VARS_YAML k8s.bookinfoCertDir)/fullchain.pem
kubectl apply -f bookinfo/cluster-t1.yaml
sleep 5
while kubectl get svc tsb-tier1 -n t1 | grep pending | wc -l | grep 0 ; [ $? -ne 0 ]; do
    echo Tier 1 Gateway IP not assigned
    sleep 5s
done
export T1_GATEWAY_IP=$(kubectl get service tsb-tier1 -n t1 -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
export T1_GATEWAY_IP_OLD=$(nslookup $(yq r $VARS_YAML bookinfo.fqdn) | grep 'Address:' | tail -n1 | awk '{print $2}')
gcloud beta dns --project=$(yq r $VARS_YAML gcp.env) record-sets transaction start --zone=$(yq r $VARS_YAML gcp.acme.dnsZoneId)
gcloud beta dns --project=$(yq r $VARS_YAML gcp.env) record-sets transaction remove $T1_GATEWAY_IP_OLD --name=$(yq r $VARS_YAML bookinfo.fqdn). --ttl=300 --type=A --zone=$(yq r $VARS_YAML gcp.acme.dnsZoneId)
gcloud beta dns --project=$(yq r $VARS_YAML gcp.env) record-sets transaction add $T1_GATEWAY_IP --name=$(yq r $VARS_YAML bookinfo.fqdn). --ttl=300 --type=A --zone=$(yq r $VARS_YAML gcp.acme.dnsZoneId)
gcloud beta dns --project=$(yq r $VARS_YAML gcp.env) record-sets transaction execute --zone=$(yq r $VARS_YAML gcp.acme.dnsZoneId)
echo “Old Tier 1 ip: $T1_GATEWAY_IP_OLD
echo “New Tier 1 ip: $T1_GATEWAY_IP

kubectl apply -f bookinfo/tmp1.yaml
for i in {1..50}
do
   curl -vv http://$T1_GATEWAY_IP
done
kubectl delete -f bookinfo/tmp1.yaml

while nslookup $(yq r $VARS_YAML bookinfo.fqdn) | grep $T1_GATEWAY_IP ; [ $? -ne 0 ]; do
	echo Tier1 Gateway DNS is not yet propagated
	sleep 5s
done
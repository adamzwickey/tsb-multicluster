#!/usr/bin/env bash
: ${VARS_YAML?"Need to set VARS_YAML environment variable"}

echo "Deploying Keycloak Application"

#ingress
kubectl create clusterrolebinding cluster-admin-binding \
  --clusterrole cluster-admin \
  --user $(gcloud config get-value account)
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v0.48.1/deploy/static/provider/cloud/deploy.yaml
sleep 5
while kubectl get svc ingress-nginx-controller -n ingress-nginx | grep pending | wc -l | grep 0 ; [ $? -ne 0 ]; do
    echo Ingress IP not assigned
    sleep 5
done

echo "Configuring DNS for Keycloak..."
export KEYCLOAK_IP_OLD=$(nslookup $(yq eval .keycloak.fqdn $VARS_YAML) | grep 'Address:' | tail -n1 | awk '{print $2}')
export KEYCLOAK_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o json --output jsonpath='{.status.loadBalancer.ingress[0].ip}')  
gcloud beta dns --project=$(yq eval .gcp.env $VARS_YAML) record-sets transaction start --zone=$(yq eval .gcp.acme.dnsZoneId $VARS_YAML)
gcloud beta dns --project=$(yq eval .gcp.env $VARS_YAML) record-sets transaction remove $KEYCLOAK_IP_OLD --name=$(yq eval .keycloak.fqdn $VARS_YAML). --ttl=300 --type=A --zone=$(yq eval .gcp.acme.dnsZoneId $VARS_YAML)
gcloud beta dns --project=$(yq eval .gcp.env $VARS_YAML) record-sets transaction add $KEYCLOAK_IP --name=$(yq eval .keycloak.fqdn $VARS_YAML). --ttl=300 --type=A --zone=$(yq eval .gcp.acme.dnsZoneId $VARS_YAML)
gcloud beta dns --project=$(yq eval .gcp.env $VARS_YAML) record-sets transaction execute --zone=$(yq eval .gcp.acme.dnsZoneId $VARS_YAML)
echo “Old keycloak ip: $KEYCLOAK_IP_OLD
echo “New keycloak ip: $KEYCLOAK_IP

while nslookup $(yq eval .keycloak.fqdn $VARS_YAML) | grep $KEYCLOAK_IP ; [ $? -ne 0 ]; do
	echo Keycloak DNS is not yet propagated
	sleep 5
done

# TODO keycloak.yaml has hardcoded zwickey.net URLs... externalized
kubectl apply -f keycloak/keycloak.yaml

while kubectl get certificates.cert-manager.io -n keycloak keycloak-certs | grep True; [ $? -ne 0 ]; do
	echo Keycloak Certificate is not yet ready
	sleep 5
done

URL=$(yq eval .keycloak.fqdn $VARS_YAML)
export TOKEN=$(curl --location --request POST https://$URL/auth/realms/master/protocol/openid-connect/token \
--header 'Content-Type: application/x-www-form-urlencoded' \
--data-urlencode 'username=admin' \
--data-urlencode 'password=t3trat3!' \
--data-urlencode 'grant_type=password' \
--data-urlencode 'client_id=admin-cli' | jq -r '.access_token')
echo token: $TOKEN
# TODO tetrate-realm.json has hardcoded zwickey.net URLs... externalized
curl --location --request POST https://$URL/auth/admin/realms \
   -H "Content-Type: application/json" \
   -H "Authorization: bearer $TOKEN"  \
   --data @keycloak/tetrate-realm.json
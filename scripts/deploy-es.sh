#!/usr/bin/env bash
: ${VARS_YAML?"Need to set VARS_YAML environment variable"}

echo "Deploying Elastic Search"

helm repo add elastic https://helm.elastic.co
kubectl create ns elastic

#Secrets for internal TLS
docker rm -f elastic-helm-charts-certs || true
rm -f elastic-certificates.p12 elastic-certificate.pem elastic-certificate.crt elastic-stack-ca.p12 || true
docker run --name elastic-helm-charts-certs -i -w /tmp \
  docker.elastic.co/elasticsearch/elasticsearch:8.0.0-SNAPSHOT \
  /bin/sh -c " \
    elasticsearch-certutil ca --out /tmp/elastic-stack-ca.p12 --pass '' && \
    elasticsearch-certutil cert --name security-master --dns security-master --ca /tmp/elastic-stack-ca.p12 --pass '' --ca-pass '' --out /tmp/elastic-certificates.p12" && \
docker cp elastic-helm-charts-certs:/tmp/elastic-certificates.p12 ./ && \
docker rm -f elastic-helm-charts-certs && \
openssl pkcs12 -nodes -passin pass:'' -in elastic-certificates.p12 -out elastic-certificate.pem && \
openssl x509 -outform der -in elastic-certificate.pem -out elastic-certificate.crt && \
kubectl create secret generic -n elastic elastic-certificates --from-file=elastic-certificates.p12 && \
kubectl create secret generic -n elastic elastic-certificate-pem --from-file=elastic-certificate.pem && \
kubectl create secret generic -n elastic elastic-certificate-crt --from-file=elastic-certificate.crt && \
rm -f elastic-certificates.p12 elastic-certificate.pem elastic-certificate.crt elastic-stack-ca.p12

cat generated/es-values.yaml | helm install elasticsearch elastic/elasticsearch --namespace elastic -f - 

echo "Configuring DNS for Elastic Search..."
export ES_IP_OLD=$(nslookup elastic.tetrate.zwickey.net | grep 'Address:' | tail -n1 | awk '{print $2}')
export ES_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o json --output jsonpath='{.status.loadBalancer.ingress[0].ip}')  
gcloud beta dns --project=$(yq r $VARS_YAML gcp.env) record-sets transaction start --zone=$(yq r $VARS_YAML gcp.acme.dnsZoneId)
gcloud beta dns --project=$(yq r $VARS_YAML gcp.env) record-sets transaction remove $ES_IP_OLD --name=elastic.tetrate.zwickey.net. --ttl=300 --type=A --zone=$(yq r $VARS_YAML gcp.acme.dnsZoneId)
gcloud beta dns --project=$(yq r $VARS_YAML gcp.env) record-sets transaction add $ES_IP --name=elastic.tetrate.zwickey.net. --ttl=300 --type=A --zone=$(yq r $VARS_YAML gcp.acme.dnsZoneId)
gcloud beta dns --project=$(yq r $VARS_YAML gcp.env) record-sets transaction execute --zone=$(yq r $VARS_YAML gcp.acme.dnsZoneId)
echo “Old Elastic ip: $ES_IP_OLD
echo “New Elastic ip: $ES_IP

while nslookup elastic.tetrate.zwickey.net | grep $ES_IP ; [ $? -ne 0 ]; do
	echo Elastic Search DNS is not yet propagated
	sleep 5
done

curl -vvv https://elastic.tetrate.zwickey.net
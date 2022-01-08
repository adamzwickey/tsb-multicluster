#!/usr/bin/env bash
: ${VARS_YAML?"Need to set VARS_YAML environment variable"}
: ${1?"Must supply cluster name arg"}

export CLUSTER_NAME=$1

echo "Deploying Workload Cluster $CLUSTER_NAME Control Plane"
kubectl create ns istio-system
kubectl create secret generic cacerts -n istio-system \
  --from-file=$(yq eval .k8s.istioCertDir $VARS_YAML)/ca-cert.pem \
  --from-file=$(yq eval .k8s.istioCertDir $VARS_YAML)/ca-key.pem \
  --from-file=$(yq eval .k8s.istioCertDir $VARS_YAML)/root-cert.pem \
  --from-file=$(yq eval .k8s.istioCertDir $VARS_YAML)/cert-chain.pem
kubectl apply -f generated/$CLUSTER_NAME/cp-operator.yaml
kubectl apply -f generated/$CLUSTER_NAME/cluster-certs.yaml
kubectl apply -f generated/$CLUSTER_NAME/cluster-secrets.yaml
while kubectl get po -n istio-system -l name=tsb-operator | grep Running | wc -l | grep 1 ; [ $? -ne 0 ]; do
    echo TSB Operator is not yet ready
    sleep 5
done
sleep 30 # Dig into why this is needed
cp control-plane.yaml generated/$CLUSTER_NAME/
export REGISTRY=$(yq eval .tetrate.registry $VARS_YAML)
export MP=$(yq eval .gcp.mgmt.fqdn $VARS_YAML)
yq e -i '.spec.hub=strenv(REGISTRY) |
        .spec.telemetryStore.elastic.host=strenv(MP) |
        .spec.managementPlane.host=strenv(MP) |
        .spec.managementPlane.clusterName=strenv(CLUSTER_NAME)' generated/$CLUSTER_NAME/control-plane.yaml
kubectl apply -f generated/$CLUSTER_NAME/control-plane.yaml
#Edge Pod is the last thing to start
while kubectl get po -n istio-system -l app=edge | grep Running | wc -l | grep 1 ; [ $? -ne 0 ]; do
    echo Istio control plane is not yet ready
    sleep 5
done
kubectl patch ControlPlane controlplane -n istio-system --patch '{"spec":{"meshExpansion":{}}}' --type merge



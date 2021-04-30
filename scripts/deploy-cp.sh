#!/usr/bin/env bash
: ${VARS_YAML?"Need to set VARS_YAML environment variable"}
: ${1?"Must supply cluster name arg"}

CLUSTER_NAME=$1

echo "Deploying Workload Cluster $CLUSTER_NAME Control Plane"
kubectl create ns istio-system
  kubectl create secret generic cacerts -n istio-system \
    --from-file=$(yq r $VARS_YAML k8s.istioCertDir)/ca-cert.pem \
    --from-file=$(yq r $VARS_YAML k8s.istioCertDir)/ca-key.pem \
    --from-file=$(yq r $VARS_YAML k8s.istioCertDir)/root-cert.pem \
    --from-file=$(yq r $VARS_YAML k8s.istioCertDir)/cert-chain.pem
  kubectl apply -f generated/$CLUSTER_NAME/cp-operator.yaml
  kubectl apply -f generated/$CLUSTER_NAME/cluster-certs.yaml
  kubectl apply -f generated/$CLUSTER_NAME/cluster-secrets.yaml
  while kubectl get po -n istio-system -l name=tsb-operator | grep Running | wc -l | grep 1 ; [ $? -ne 0 ]; do
      echo TSB Operator is not yet ready
      sleep 5s
  done
  sleep 30 # Dig into why this is needed
  cp control-plane.yaml generated/$CLUSTER_NAME/
  yq write generated/$CLUSTER_NAME/control-plane.yaml -i "spec.hub" $(yq r $VARS_YAML tetrate.registry)
  yq write generated/$CLUSTER_NAME/control-plane.yaml -i "spec.telemetryStore.elastic.host" $(yq r $VARS_YAML gcp.mgmt.fqdn)
  yq write generated/$CLUSTER_NAME/control-plane.yaml -i "spec.managementPlane.host" $(yq r $VARS_YAML gcp.mgmt.fqdn)
  yq write generated/$CLUSTER_NAME/control-plane.yaml -i "spec.managementPlane.clusterName" $CLUSTER_NAME
  kubectl apply -f generated/$CLUSTER_NAME/control-plane.yaml
  #Edge Pod is the last thing to start
  while kubectl get po -n istio-system -l app=edge | grep Running | wc -l | grep 1 ; [ $? -ne 0 ]; do
      echo Istio control plane is not yet ready
      sleep 5s
  done
  kubectl patch ControlPlane controlplane -n istio-system --patch '{"spec":{"meshExpansion":{}}}' --type merge



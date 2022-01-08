#!/usr/bin/env bash
: ${VARS_YAML?"Need to set VARS_YAML environment variable"}
echo config YAML:
cat $VARS_YAML

#Scale down mgmt stuff
kx gke_abz-env_us-east4_tsb-mgmt
kubectl -n tsb scale deployment oap --replicas=0
kubectl -n tsb scale deployment zipkin --replicas=0
#Scale down workloads
kx gke_abz-env_us-east4_dmz
kubectl -n istio-system scale deployment oap-deployment --replicas=0
kubectl -n istio-system scale deployment zipkin --replicas=0
kx gke_abz-env_us-east4_public-east-4
kubectl -n istio-system scale deployment oap-deployment --replicas=0
kubectl -n istio-system scale deployment zipkin --replicas=0
kx gke_abz-env_us-east4_tsb-mgmt
kubectl -n istio-system scale deployment oap-deployment --replicas=0
kubectl -n istio-system scale deployment zipkin --replicas=0
kx gke_abz-env_us-west1_public-west-4
kubectl -n istio-system scale deployment oap-deployment --replicas=0
kubectl -n istio-system scale deployment zipkin --replicas=0
rapture assume tetrate-test/admin
kx rapture-zwickey@private-east-2.us-east-2.eksctl.io
kubectl -n istio-system scale deployment oap-deployment --replicas=0
kubectl -n istio-system scale deployment zipkin --replicas=0
kx rapture-zwickey@private-west-1.us-west-1.eksctl.io
kubectl -n istio-system scale deployment oap-deployment --replicas=0
kubectl -n istio-system scale deployment zipkin --replicas=0

# Run shell to clear
kx gke_abz-env_us-east4_tsb-mgmt
kubectl run shell -n tsb --rm -i --tty --image nicolaka/netshoot -- /bin/bash 

#Scale up Mgmt
kubectl -n tsb scale deployment oap --replicas=1
kubectl -n tsb scale deployment zipkin --replicas=1
#Sleep
sleep 30
#Scale Up workloads
kx gke_abz-env_us-east4_dmz
kubectl -n istio-system scale deployment oap-deployment --replicas=1
kubectl -n istio-system scale deployment zipkin --replicas=1
kx gke_abz-env_us-east4_public-east-4
kubectl -n istio-system scale deployment oap-deployment --replicas=1
kubectl -n istio-system scale deployment zipkin --replicas=1
kx gke_abz-env_us-east4_tsb-mgmt
kubectl -n istio-system scale deployment oap-deployment --replicas=1
kubectl -n istio-system scale deployment zipkin --replicas=1
kx gke_abz-env_us-west1_public-west-4
kubectl -n istio-system scale deployment oap-deployment --replicas=1
kubectl -n istio-system scale deployment zipkin --replicas=1
rapture assume tetrate-test/admin
kx rapture-zwickey@private-east-2.us-east-2.eksctl.io
kubectl -n istio-system scale deployment oap-deployment --replicas=1
kubectl -n istio-system scale deployment zipkin --replicas=1
kx rapture-zwickey@private-west-1.us-west-1.eksctl.io
kubectl -n istio-system scale deployment oap-deployment --replicas=1
kubectl -n istio-system scale deployment zipkin --replicas=1
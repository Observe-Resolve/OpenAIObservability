#!/usr/bin/env bash

################################################################################
### Script deploying the Observ-K8s environment
### Parameters:
### Clustern name: name of your k8s cluster
### dttoken: Dynatrace api token with ingest metrics and otlp ingest scope
### dturl : url of your DT tenant wihtout any / at the end for example: https://dedede.live.dynatrace.com
################################################################################


### Pre-flight checks for dependencies
if ! command -v jq >/dev/null 2>&1; then
    echo "Please install jq before continuing"
    exit 1
fi

if ! command -v git >/dev/null 2>&1; then
    echo "Please install git before continuing"
    exit 1
fi


if ! command -v helm >/dev/null 2>&1; then
    echo "Please install helm before continuing"
    exit 1
fi

if ! command -v kubectl >/dev/null 2>&1; then
    echo "Please install kubectl before continuing"
    exit 1
fi
echo "parsing arguments"
while [ $# -gt 0 ]; do
  case "$1" in
   --dtoperatortoken)
          DTOPERATORTOKEN="$2"
         shift 2
          ;;
       --dtingesttoken)
          DTTOKEN="$2"
         shift 2
          ;;
       --dturl)
          DTURL="$2"
         shift 2
          ;;
       --clustername)
         CLUSTERNAME="$2"
         shift 2
         ;;
       --openAIendpoint)
         OPENAIHOST="$2"
        shift 2
        ;;
       --openAITOKEN)
       OPENAITOKEN="$2"
       shift 2
       ;;
  *)
    echo "Warning: skipping unsupported option: $1"
    shift
    ;;
  esac
done
echo "Checking arguments"
 if [ -z "$CLUSTERNAME" ]; then
   echo "Error: clustername not set!"
   exit 1
 fi
 if [ -z "$DTURL" ]; then
   echo "Error: Dt url not set!"
   exit 1
 fi

 if [ -z "$DTTOKEN" ]; then
   echo "Error: Data ingest api-token not set!"
   exit 1
 fi

 if [ -z "$DTOPERATORTOKEN" ]; then
   echo "Error: DT operator token not set!"
   exit 1
 fi
if [ -z "$OPENAIHOST" ]; then
   echo "Error: OpenAI host is  not set!"
   exit 1
 fi
 if [ -z "$OPENAITOKEN" ]; then
    echo "Error: OpenAI token is not set!"
    exit 1
  fi


helm upgrade --install ingress-nginx ingress-nginx  --repo https://kubernetes.github.io/ingress-nginx  --namespace ingress-nginx --create-namespace --set controller.opentelemetry.enabled=true --set controller.metrics.enabled=true \
                                                                                                                                                                                                --set-string controller.podAnnotations."prometheus\.io/scrape"="true" \
                                                                                                                                                                                                --set-string controller.podAnnotations."prometheus\.io/port"="10254"
#### Deploy the cert-manager
echo "Deploying Cert Manager ( for OpenTelemetry Operator)"
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.10.0/cert-manager.yaml
# Wait for pod webhook started
kubectl wait pod -l app.kubernetes.io/component=webhook -n cert-manager --for=condition=Ready --timeout=2m
# Deploy the opentelemetry operator
sleep 10
echo "Deploying the OpenTelemetry Operator"
kubectl apply -f https://github.com/open-telemetry/opentelemetry-operator/releases/latest/download/opentelemetry-operator.yaml
CLUSTERID=$(kubectl get namespace kube-system -o jsonpath='{.metadata.uid}');

#### Deploy the Dynatrace Operator
kubectl create namespace dynatrace
kubectl apply -f https://github.com/Dynatrace/dynatrace-operator/releases/download/v1.2.0/kubernetes.yaml
kubectl apply -f https://github.com/Dynatrace/dynatrace-operator/releases/download/v1.2.0/kubernetes-csi.yaml
kubectl -n dynatrace wait pod --for=condition=ready --selector=app.kubernetes.io/name=dynatrace-operator,app.kubernetes.io/component=webhook --timeout=300s
kubectl -n dynatrace create secret generic dynakube --from-literal="apiToken=$DTOPERATORTOKEN" --from-literal="dataIngestToken=$DTTOKEN"
sed -i "s,TENANTURL_TOREPLACE,$DTURL," dynatrace/dynakube.yaml
sed -i "s,CLUSTER_NAME_TO_REPLACE,$CLUSTERNAME,"  dynatrace/dynakube.yaml

### get the ip adress of ingress ####
IP=""
while [ -z $IP ]; do
  echo "Waiting for external IP"
  IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -ojson | jq -j '.status.loadBalancer.ingress[].ip')
   [ -z "$IP" ] && sleep 10
done
echo 'Found external IP: '$IP

### Update the ip of the ip adress for the ingres
#TODO to update this part to create the various Gateway rules
sed -i "s,IP_TO_REPLACE,$IP," k8s/deployment.yaml

#Deploy collector
kubectl create secret generic dynatrace  --from-literal=dynatrace_oltp_url="$DTURL" --from-literal=clustername="$CLUSTERNAME"  --from-literal=clusterid=$CLUSTERID  --from-literal=dt_api_token="$DTTOKEN"
kubectl label namespace  default oneagent=false
kubectl apply -f opentelemetry/rbac.yaml
kubectl apply -f opentelemetry/openTelemetry-manifest_statefulset.yaml
kubectl apply -f opentelemetry/openTelemetry-manifest_ds.yaml

#deploy demo application
kubectl create ns travel-advisor-azure
kubectl label namespace  travel-advisor-azure oneagent=false
kubectl create secret generic azure --from-literal key="$OPENAITOKEN" --from-literal endpoint="$OPENAIHOST"  -n travel-advisor-azure
kubectl apply -f k8s/deployment.yaml -n travel-advisor-azure
kubectl apply -f k8s/loadtest.yaml

kubectl apply -f dynatrace/dynakube.yaml -n dynatrace

#Deploy the ingress rules
echo "--------------Demo--------------------"
echo "url of the demo: "
echo " post-demo url : http://traveladvisor.$IP.nip.io"
echo "========================================================"



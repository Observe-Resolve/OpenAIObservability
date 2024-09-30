
# Observe & Resolve
<p align="center"><img src="/image/logo.png" width="40%" alt="Observe & Resolve logo" /></p>


## Episode : Analyze the OpenAI application
This repository contains the files utilized during the tutorial presented in the dedicated Observe&Resolve episode related to Observing AI/LLM Application.
<p align="center"><img src="/image/openAI.png" width="40%" alt="OpenAI Logo" /></p>

this tutorial will also utilize the Dynatrace with : 
* OpenAI demo application instrumented with [OpenLLmetry](https://github.com/traceloop/openllmetry)
* The openTelemtry Collector to report the traces, logs and metrics
* The Dynatrace Operator to report the health on our k8s objects

All the observability data generated by the environment would be sent to Dynatrace.


![preview](./dashboard/OpenAI-dashboard.png)



### 1.Create a Google Cloud Platform Project
```shell
PROJECT_ID="<your-project-id>"
gcloud services enable container.googleapis.com --project ${PROJECT_ID}
gcloud services enable monitoring.googleapis.com \
cloudtrace.googleapis.com \
clouddebugger.googleapis.com \
cloudprofiler.googleapis.com \
--project ${PROJECT_ID}
```

### 2.Create a GKE cluster
```shell
ZONE=europe-west3-a
NAME=observeresolve-openai
gcloud container clusters create ${NAME} --zone=${ZONE} --machine-type=e2-standard-4 --num-nodes=2
```
### 3. Clone Github repo

```shell
git clone  https://github.com/Observe&Resolve/OpenAIObservability
cd OpenAIObservability
```

## Getting started



### Dynatrace Tenant
#### 1. Dynatrace Tenant - start a trial
If you don't have any Dynatrace tenant , then I suggest to create a trial using the following link : [Dynatrace Trial](https://dt-url.net/observable-trial)
Once you have your Tenant save the Dynatrace tenant url in the variable `DT_TENANT_URL` (for example : https://dedededfrf.live.dynatrace.com)
```
DT_TENANT_URL=<YOUR TENANT Host>
```

##### 2. Create the Dynatrace API Tokens
The dynatrace operator will require to have several tokens:
* Token to deploy and configure the various components
* Token to ingest metrics and Traces


###### Operator Token
One for the operator having the following scope:
* Create ActiveGate tokens
* Read entities
* Read Settings
* Write Settings
* Access problem and event feed, metrics and topology
* Read configuration
* Write configuration
* Paas integration - installer downloader
<p align="center"><img src="/image/operator_token.png" width="40%" alt="operator token" /></p>

Save the value of the token . We will use it later to store in a k8S secret
```shell
API_TOKEN=<YOUR TOKEN VALUE>
```
###### Ingest data token
Create a Dynatrace token with the following scope:
* Ingest metrics (metrics.ingest)
* Ingest logs (logs.ingest)
* Ingest events (events.ingest)
* Ingest OpenTelemetry
* Read metrics
<p align="center"><img src="/image/data_ingest_token.png" width="40%" alt="data token" /></p>
Save the value of the token . We will use it later to store in a k8S secret

```shell
DATA_INGEST_TOKEN=<YOUR TOKEN VALUE>
```

### AZURE OpenAI 
You will have to provision a [Azure AI OpenAI service](https://learn.microsoft.com/en-us/azure/ai-services/openai/reference)
#### 1. OpenAI Endpoint
```shell
AZURE_OPENAI_ENDPOINT="<YOUR OPENAI ENDPOINT>"
```
#### 2. OpenAI Token
AZURE_OPENAI_KEY> --from-literal endpoint=<AZURE_OPENAI_ENDPOINT>  -n travel-advisor-azure
```shell
AZURE_OPENAI_KEY="<YOUR OPENAI KEY>"
```

### Deploy most of the components
The application will deploy the entire environment:
```shell
chmod 777 deployment.sh
./deployment.sh  --clustername "${NAME}" --dturl "${DT_TENANT_URL}" --dtingesttoken "${DATA_INGEST_TOKEN}" --dtoperatortoken "${API_TOKEN}" --openAIendpoint "${AZURE_OPENAI_ENDPOINT}" --openAITOKEN "${AZURE_OPENAI_KEY}"
```



## Observability

You can import the OpenAI dashboard available in the [dashboard](./dashboard) directory to have out of the box observability of key metrics of your OpenAI application.

![preview](./dashboard/OpenAI-dashboard.png)
from openai import AzureOpenAI

import logging
import os
from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles
import uvicorn

from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from traceloop.sdk import Traceloop
from traceloop.sdk.decorators import workflow

os.environ["TRACELOOP_TELEMETRY"] = "false"

def read_dt_token():
    return read_secret('token')

def read_azure_key():
    return read_secret('key')

def read_azure_endpoint():
    return read_secret('endpoint')

def read_secret(secret: str):
    try:
        with open(f"/etc/secrets/{secret}", "r") as f:
            return f.read().rstrip()
    except Exception as e:
        print("No token was provided")
        print(e)
        return ""


# GLOBALS
AI_MODEL = os.environ.get("AI_MODEL", "genai-demo")
AI_EMBEDDING_MODEL = os.environ.get("AI_EMBEDDING_MODEL", "text-embedding-ada-002")
OTEL_ENDPOINT = os.environ.get("OTEL_ENDPOINT", "https://xbw95514.dev.dynatracelabs.com/api/v2/otlp")

if OTEL_ENDPOINT.endswith("/v1/traces"):
    OTEL_ENDPOINT = OTEL_ENDPOINT[:OTEL_ENDPOINT.find("/v1/traces")]

# Initialise the logger
logging.basicConfig(level=logging.INFO, filename="run.log")
logger = logging.getLogger(__name__)

# ################
# # CONFIGURE OPENTELEMETRY

resource = Resource.create({
    "service.name": "travel-advisor-azure",
    "service.version": "0.1.0"
})

TOKEN = read_dt_token()
headers = {
    "Authorization": f"Api-Token {TOKEN}"
}

provider = TracerProvider(resource=resource)
#processor = BatchSpanProcessor(OTLPSpanExporter(endpoint=f"{OTEL_ENDPOINT}/v1/traces", headers=headers))
#provider.add_span_processor(processor)
trace.set_tracer_provider(provider)
otel_tracer = trace.get_tracer("travel.advisor")

Traceloop.init(app_name="travel-advisor-azure", api_endpoint=OTEL_ENDPOINT, disable_batch=True, headers=headers)

MAX_PROMPT_LENGTH = 50
retrieval_chain = None

############
# CONFIGURE ENDPOINTS

app = FastAPI()

client = AzureOpenAI(
    api_key=read_azure_key(),
    api_version="2024-07-01-preview",
    azure_endpoint=read_azure_endpoint(),
)


####################################
@app.get("/api/v1/completion")
def submit_completion(prompt: str):
    with otel_tracer.start_as_current_span(name="/api/v1/completion") as span:
        return submit_completion(prompt, span)


@workflow(name="travelgenerator")
def submit_completion(prompt: str, span):
        if prompt:
            curated_prompt = f"""
            1. Answer the question at the end as travel advise.
            2. Keep the answer crisp and limited to 3,4 sentences.
            
            Question: {prompt}"""
            chat_completion = client.chat.completions.create(
                messages=[{ "role": "user", "content": curated_prompt }],
                model=AI_MODEL,
                temperature=0.1,
            )
            message = ""
            if chat_completion and hasattr(chat_completion, 'choices'):
                message = chat_completion.choices.pop().message.content
            return {"message": message}
        else:  # No, or invalid prompt given
            span.add_event(f"No prompt provided or prompt too long (over {MAX_PROMPT_LENGTH} chars)")
            return {"message": f"No prompt provided or prompt too long (over {MAX_PROMPT_LENGTH} chars)"}


####################################
@app.get("/api/v1/thumbsUp")
@otel_tracer.start_as_current_span("/api/v1/thumbsUp")
def thumbs_up(prompt: str):
    logger.info(f"Positive user feedback for search term: {prompt}")


@app.get("/api/v1/thumbsDown")
@otel_tracer.start_as_current_span("/api/v1/thumbsDown")
def thumbs_down(prompt: str):
    logger.info(f"Negative user feedback for search term: {prompt}")


if __name__ == "__main__":

    # Mount static files at the root
    app.mount("/", StaticFiles(directory="./public", html=True), name="public")
    #app.mount("/destinations", StaticFiles(directory="destinations", html = True), name="destinations")

    # Run the app using uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080)

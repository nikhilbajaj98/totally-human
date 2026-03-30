import os
import time
from urllib.parse import urlparse

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from curl_cffi import requests

from logging_config import logger
from model import RequestPayload, ResponsePayload

app = FastAPI(title="Mask Service", version="0.1.0")

# Tunables
MAX_HTML_CHARS = int(os.getenv("MAX_HTML_CHARS", "100000"))
ALLOW_INSECURE_SSL = os.getenv("ALLOW_INSECURE_SSL", "false").lower() == "true"
DEFAULT_TIMEOUT = float(os.getenv("REQUEST_TIMEOUT_SECONDS", "30"))
USER_AGENT = os.getenv(
    "MASK_SERVICE_USER_AGENT",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
)

COMMON_HEADERS = {
    "User-Agent": USER_AGENT,
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "en-US,en;q=0.9",
}


@app.get("/")
def read_root():
    return {"message": "mask-service: ok"}


@app.middleware("http")
async def log_requests(request: Request, call_next):
    start = time.time()
    response = await call_next(request)
    duration_ms = (time.time() - start) * 1000
    # Include key fields in the message to avoid formatter issues
    logger.info(
        "request path=%s method=%s status=%s duration_ms=%.1f",
        request.url.path,
        request.method,
        response.status_code,
        duration_ms,
    )
    return response


@app.post("/v1/request")
def request(payload: RequestPayload):
    """
    Fetch a URL using curl_cffi with Chrome TLS fingerprint spoofing.
    """
    try:
        # Validate URL
        parsed = urlparse(payload.url)
        if (
            parsed.scheme not in {"http", "https"}
            or not parsed.netloc
            or not parsed.hostname
        ):
            return JSONResponse(
                status_code=400,
                content={
                    "error": True,
                    "error_message": "Invalid url: must include scheme http/https and host",
                    "status": 400,
                    "headers": {},
                    "html": "",
                },
            )

        # Prepare proxy dict if provided (validate basic format)
        proxies = None
        if payload.proxy:
            proxy_parsed = urlparse(payload.proxy)
            if (
                proxy_parsed.scheme not in {"http", "https", "socks5", "socks5h"}
                or not proxy_parsed.netloc
            ):
                return JSONResponse(
                    status_code=400,
                    content={
                        "error": True,
                        "error_message": "Invalid proxy: must be a full URL with scheme (http/https/socks5)",
                        "status": 400,
                        "headers": {},
                        "html": "",
                    },
                )
            proxy_host = proxy_parsed.hostname
            proxy_port = f":{proxy_parsed.port}" if proxy_parsed.port else ""
            logger.info(
                "Using proxy: %s://%s%s", proxy_parsed.scheme, proxy_host, proxy_port
            )
            proxies = {
                "http": payload.proxy,
                "https": payload.proxy,
            }

        logger.info("Making request to %s with proxy=%s", payload.url, bool(proxies))

        response = requests.get(
            payload.url,
            impersonate="chrome120",
            proxies=proxies,
            timeout=DEFAULT_TIMEOUT,
            verify=not ALLOW_INSECURE_SSL,
            headers=COMMON_HEADERS,
        )
        logger.info("Response status: %s", response.status_code)

        headers_dict = dict(response.headers)
        body = response.text
        if len(body) > MAX_HTML_CHARS:
            logger.warning(
                "Truncating response body",
                extra={"original_length": len(body), "max_html_chars": MAX_HTML_CHARS},
            )
            body = body[:MAX_HTML_CHARS]

        return ResponsePayload(
            status=response.status_code,
            html=body,
            headers=headers_dict,
            error=False,
            error_message=None,
        )

    except Exception as e:
        logger.error("Error fetching %s: %s", payload.url, str(e), exc_info=True)
        return ResponsePayload(
            status=500,
            html="",
            headers={},
            error=True,
            error_message=str(e),
        )

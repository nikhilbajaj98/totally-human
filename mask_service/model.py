from pydantic import BaseModel
from typing import Optional


class RequestPayload(BaseModel):
    url: str
    proxy: Optional[str] = None


class ResponsePayload(BaseModel):
    status: int
    html: str
    headers: dict
    error: bool = False
    error_message: Optional[str] = None



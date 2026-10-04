"""Reconciliation service (FastAPI): matches payments against bank statement entries."""
import os

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

from reconciliation_service.matching import reconcile

app = FastAPI(title="reconciliation-service", docs_url=None, redoc_url=None, openapi_url=None)


class Entry(BaseModel):
    reference: str = Field(min_length=1, max_length=64)
    amount: float = Field(gt=0, le=1_000_000_000)


class MatchRequest(BaseModel):
    payments: list[Entry] = Field(max_length=10000)
    bank_entries: list[Entry] = Field(max_length=10000)


@app.middleware("http")
async def security_headers(request, call_next):
    response = await call_next(request)
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["Content-Security-Policy"] = "default-src 'none'; frame-ancestors 'none'"
    response.headers["Referrer-Policy"] = "no-referrer"
    response.headers["Cache-Control"] = "no-store"
    return response


@app.get("/reconciliation/healthz")
def healthz():
    return {"status": "ok"}


@app.get("/reconciliation/version")
def version():
    return {"service": "reconciliation-service", "imageTag": os.getenv("IMAGE_TAG", "dev")}


@app.post("/reconciliation/match")
def match(request: MatchRequest):
    try:
        result = reconcile(
            [entry.model_dump() for entry in request.payments],
            [entry.model_dump() for entry in request.bank_entries],
        )
    except ValueError as error:
        raise HTTPException(status_code=422, detail=str(error)) from error
    result["summary"] = {
        "payments": len(request.payments),
        "bank_entries": len(request.bank_entries),
        "matched": len(result["matched"]),
    }
    return result

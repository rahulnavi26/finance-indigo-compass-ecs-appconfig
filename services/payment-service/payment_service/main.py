"""Payment service (FastAPI): accepts payments; the response flow depends on a feature flag."""
import os
import uuid
from datetime import datetime, timezone

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

from payment_service.flags import current_flags

# API docs are switched off to keep the exposed surface small
app = FastAPI(title="payment-service", docs_url=None, redoc_url=None, openapi_url=None)

_PAYMENTS: dict = {}  # in-memory store: this is a demo service, not a ledger


class PaymentRequest(BaseModel):
    amount: float = Field(gt=0, le=1_000_000)
    currency: str = Field(pattern=r"^[A-Z]{3}$")
    reference: str = Field(min_length=1, max_length=64)


@app.middleware("http")
async def security_headers(request, call_next):
    response = await call_next(request)
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["Content-Security-Policy"] = "default-src 'none'; frame-ancestors 'none'"
    response.headers["Referrer-Policy"] = "no-referrer"
    response.headers["Cache-Control"] = "no-store"
    return response


@app.get("/payments/healthz")
def healthz():
    return {"status": "ok"}


@app.get("/payments/version")
def version():
    return {"service": "payment-service", "imageTag": os.getenv("IMAGE_TAG", "dev")}


@app.get("/payments/flags")
def flags():
    return current_flags()


@app.post("/payments", status_code=201)
def create_payment(request: PaymentRequest):
    flow = "v2" if current_flags()["new_payment_flow"] else "v1"
    payment_id = str(uuid.uuid4())
    record = {
        "id": payment_id,
        "amount": request.amount,
        "currency": request.currency,
        "reference": request.reference,
        "status": "accepted",
        "flow": flow,
        "createdAt": datetime.now(timezone.utc).isoformat(),
    }
    _PAYMENTS[payment_id] = record
    return record


@app.get("/payments/{payment_id}")
def get_payment(payment_id: str):
    record = _PAYMENTS.get(payment_id)
    if record is None:
        raise HTTPException(status_code=404, detail="payment not found")
    return record

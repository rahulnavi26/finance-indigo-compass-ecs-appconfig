import pytest
from fastapi.testclient import TestClient

from payment_service import flags as flag_module
from payment_service.main import app

client = TestClient(app)

VALID = {"amount": 250.75, "currency": "INR", "reference": "INV-1001"}


@pytest.fixture(autouse=True)
def isolated_flags(monkeypatch):
    # No cache between requests, and no AppConfig agent unless a test sets one up
    monkeypatch.setattr(flag_module, "FLAG_TTL_SECONDS", 0)
    monkeypatch.delenv("APPCONFIG_PATH", raising=False)


def test_healthz():
    response = client.get("/payments/healthz")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_version_defaults_to_dev(monkeypatch):
    monkeypatch.delenv("IMAGE_TAG", raising=False)
    assert client.get("/payments/version").json()["imageTag"] == "dev"


def test_version_reports_image_tag(monkeypatch):
    monkeypatch.setenv("IMAGE_TAG", "build-42")
    body = client.get("/payments/version").json()
    assert body == {"service": "payment-service", "imageTag": "build-42"}


def test_create_payment_uses_v1_when_flag_is_off():
    response = client.post("/payments", json=VALID)
    assert response.status_code == 201
    body = response.json()
    assert body["status"] == "accepted"
    assert body["flow"] == "v1"
    assert body["reference"] == "INV-1001"


def test_create_payment_uses_v2_when_flag_is_on(monkeypatch):
    monkeypatch.setattr(flag_module, "fetch_flags", lambda: {"new_payment_flow": True})
    response = client.post("/payments", json=VALID)
    assert response.status_code == 201
    assert response.json()["flow"] == "v2"


def test_flags_endpoint_reports_defaults():
    assert client.get("/payments/flags").json() == {"new_payment_flow": False}


def test_payment_can_be_read_back():
    created = client.post("/payments", json=VALID).json()
    fetched = client.get("/payments/" + created["id"])
    assert fetched.status_code == 200
    assert fetched.json()["id"] == created["id"]


def test_unknown_payment_returns_404():
    assert client.get("/payments/does-not-exist").status_code == 404


@pytest.mark.parametrize(
    "bad",
    [
        {**VALID, "amount": 0},
        {**VALID, "amount": -5},
        {**VALID, "amount": 2_000_000},
        {**VALID, "currency": "rupees"},
        {**VALID, "reference": ""},
        {"amount": 10},
    ],
)
def test_invalid_payments_are_rejected(bad):
    assert client.post("/payments", json=bad).status_code == 422


def test_security_headers_are_set():
    headers = client.get("/payments/healthz").headers
    assert headers["x-content-type-options"] == "nosniff"
    assert headers["x-frame-options"] == "DENY"
    assert "default-src 'none'" in headers["content-security-policy"]
    assert headers["cache-control"] == "no-store"

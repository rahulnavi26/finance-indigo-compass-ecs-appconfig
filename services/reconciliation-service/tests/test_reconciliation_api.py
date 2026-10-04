import pytest
from fastapi.testclient import TestClient

from reconciliation_service.main import app
from reconciliation_service.matching import reconcile

client = TestClient(app)


def test_healthz():
    response = client.get("/reconciliation/healthz")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_version_defaults_to_dev(monkeypatch):
    monkeypatch.delenv("IMAGE_TAG", raising=False)
    assert client.get("/reconciliation/version").json()["imageTag"] == "dev"


def test_version_reports_image_tag(monkeypatch):
    monkeypatch.setenv("IMAGE_TAG", "build-7")
    body = client.get("/reconciliation/version").json()
    assert body == {"service": "reconciliation-service", "imageTag": "build-7"}


def test_match_endpoint_reports_all_categories():
    payload = {
        "payments": [
            {"reference": "A", "amount": 100},
            {"reference": "B", "amount": 50.5},
            {"reference": "C", "amount": 75},
        ],
        "bank_entries": [
            {"reference": "A", "amount": 100.00},
            {"reference": "B", "amount": 50.0},
            {"reference": "Z", "amount": 10},
        ],
    }
    response = client.post("/reconciliation/match", json=payload)
    assert response.status_code == 200
    body = response.json()
    assert body["matched"] == ["A"]
    assert body["amount_mismatch"] == [
        {"reference": "B", "payment_amount": "50.50", "bank_amount": "50.00"}
    ]
    assert body["missing_in_bank"] == ["C"]
    assert body["unexpected_in_bank"] == ["Z"]
    assert body["summary"] == {"payments": 3, "bank_entries": 3, "matched": 1}


def test_duplicate_references_are_rejected():
    payload = {
        "payments": [{"reference": "A", "amount": 1}, {"reference": "A", "amount": 2}],
        "bank_entries": [],
    }
    response = client.post("/reconciliation/match", json=payload)
    assert response.status_code == 422
    assert "duplicate reference" in response.json()["detail"]


@pytest.mark.parametrize(
    "bad",
    [
        {"payments": [{"reference": "A", "amount": 0}], "bank_entries": []},
        {"payments": [{"reference": "", "amount": 5}], "bank_entries": []},
        {"payments": []},
    ],
)
def test_invalid_requests_are_rejected(bad):
    assert client.post("/reconciliation/match", json=bad).status_code == 422


def test_security_headers_are_set():
    headers = client.get("/reconciliation/healthz").headers
    assert headers["x-content-type-options"] == "nosniff"
    assert headers["x-frame-options"] == "DENY"
    assert headers["cache-control"] == "no-store"


def test_amounts_compare_equal_regardless_of_formatting():
    result = reconcile(
        [{"reference": "A", "amount": 10.5}],
        [{"reference": "A", "amount": "10.50"}],
    )
    assert result["matched"] == ["A"]
    assert result["amount_mismatch"] == []


def test_empty_inputs_give_empty_result():
    result = reconcile([], [])
    assert result == {
        "matched": [],
        "amount_mismatch": [],
        "missing_in_bank": [],
        "unexpected_in_bank": [],
    }

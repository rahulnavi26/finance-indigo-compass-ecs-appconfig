import http.client

import pytest

from payment_service import flags as flag_module


class FakeResponse:
    def __init__(self, status, body):
        self.status = status
        self._body = body

    def read(self):
        return self._body


def fake_connection(status=200, body=b"{}", error=None):
    class FakeConnection:
        def __init__(self, host, port, timeout=None):
            pass

        def request(self, method, path):
            if error is not None:
                raise error

        def getresponse(self):
            return FakeResponse(status, body)

        def close(self):
            pass

    return FakeConnection


@pytest.fixture(autouse=True)
def with_agent_path(monkeypatch):
    monkeypatch.setenv("APPCONFIG_PATH", "/applications/fin-dev/environments/dev/configurations/flags")


def use_agent(monkeypatch, **kwargs):
    monkeypatch.setattr(http.client, "HTTPConnection", fake_connection(**kwargs))


def test_flag_enabled_by_agent(monkeypatch):
    use_agent(monkeypatch, body=b'{"new_payment_flow": true}')
    assert flag_module.fetch_flags() == {"new_payment_flow": True}


def test_flag_disabled_by_agent(monkeypatch):
    use_agent(monkeypatch, body=b'{"new_payment_flow": false}')
    assert flag_module.fetch_flags() == {"new_payment_flow": False}


def test_no_agent_path_means_defaults(monkeypatch):
    monkeypatch.delenv("APPCONFIG_PATH")
    assert flag_module.fetch_flags() == {"new_payment_flow": False}


def test_agent_error_status_falls_back_to_defaults(monkeypatch):
    use_agent(monkeypatch, status=500, body=b'{"new_payment_flow": true}')
    assert flag_module.fetch_flags() == {"new_payment_flow": False}


def test_invalid_json_falls_back_to_defaults(monkeypatch):
    use_agent(monkeypatch, body=b"not json")
    assert flag_module.fetch_flags() == {"new_payment_flow": False}


def test_unreachable_agent_falls_back_to_defaults(monkeypatch):
    use_agent(monkeypatch, error=ConnectionRefusedError())
    assert flag_module.fetch_flags() == {"new_payment_flow": False}


def test_non_boolean_values_are_ignored(monkeypatch):
    use_agent(monkeypatch, body=b'{"new_payment_flow": "yes"}')
    assert flag_module.fetch_flags() == {"new_payment_flow": False}


def test_non_object_json_is_ignored(monkeypatch):
    use_agent(monkeypatch, body=b"[1, 2, 3]")
    assert flag_module.fetch_flags() == {"new_payment_flow": False}


def test_current_flags_caches_between_calls(monkeypatch):
    calls = []

    def counting_fetch():
        calls.append(1)
        return {"new_payment_flow": True}

    monkeypatch.setattr(flag_module, "fetch_flags", counting_fetch)
    monkeypatch.setattr(flag_module, "FLAG_TTL_SECONDS", 1000)
    monkeypatch.setitem(flag_module._cache, "at", None)

    assert flag_module.current_flags() == {"new_payment_flow": True}
    assert flag_module.current_flags() == {"new_payment_flow": True}
    assert len(calls) == 1

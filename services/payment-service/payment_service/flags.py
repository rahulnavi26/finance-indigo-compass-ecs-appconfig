"""Feature flags read from the AWS AppConfig agent sidecar (127.0.0.1:2772).

Fail-safe by design: if the agent is missing, slow or returns anything unexpected,
every flag stays at its default (OFF), so a flag outage can never switch a new
payment flow on by accident.
"""
import http.client
import json
import os
import time

AGENT_HOST = "127.0.0.1"
AGENT_PORT = 2772
FLAG_TTL_SECONDS = 5.0
DEFAULT_FLAGS = {"new_payment_flow": False}

_cache = {"at": None, "flags": dict(DEFAULT_FLAGS)}


def fetch_flags() -> dict:
    """Ask the AppConfig agent for the current flags; fall back to defaults on any problem."""
    flags = dict(DEFAULT_FLAGS)
    path = os.getenv("APPCONFIG_PATH", "")
    if not path:
        return flags
    try:
        conn = http.client.HTTPConnection(AGENT_HOST, AGENT_PORT, timeout=1)
        try:
            conn.request("GET", path)
            response = conn.getresponse()
            if response.status != 200:
                return flags
            loaded = json.loads(response.read().decode("utf-8"))
        finally:
            conn.close()
    except (OSError, ValueError, http.client.HTTPException):
        return flags
    if isinstance(loaded, dict):
        for name in DEFAULT_FLAGS:
            if isinstance(loaded.get(name), bool):
                flags[name] = loaded[name]
    return flags


def current_flags() -> dict:
    """Flags with a short cache so we do not call the agent on every request."""
    now = time.monotonic()
    if _cache["at"] is None or now - _cache["at"] >= FLAG_TTL_SECONDS:
        _cache["flags"] = fetch_flags()
        _cache["at"] = now
    return dict(_cache["flags"])

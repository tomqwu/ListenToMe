#!/usr/bin/env python3
"""Print the preferred chat-capable Ollama model name (empty string if none).

Queries the local Ollama server's /api/tags for installed models, then probes
each via /api/show, keeping only those whose `capabilities` include
"completion" (i.e. chat models, not embedding-only). Prefers a local
(non-`:cloud`) model over a cloud one. Used by `make e2e` to auto-pick a model.
"""
import json
import sys
import urllib.request

BASE = "http://localhost:11434"


def chat_capable(name):
    try:
        req = urllib.request.Request(
            BASE + "/api/show",
            data=json.dumps({"model": name}).encode(),
            headers={"Content-Type": "application/json"},
        )
        with urllib.request.urlopen(req, timeout=10) as resp:
            caps = json.load(resp).get("capabilities") or []
        return "completion" in caps
    except Exception:
        return False


def main():
    try:
        with urllib.request.urlopen(BASE + "/api/tags", timeout=5) as resp:
            names = [m["name"] for m in json.load(resp).get("models", [])]
    except Exception:
        print("")
        return

    chat = [n for n in names if chat_capable(n)]
    print(next((n for n in chat if ":cloud" not in n), chat[0] if chat else ""))


if __name__ == "__main__":
    main()

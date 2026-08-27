#!/usr/bin/env python3
"""Build a provider-specific JSON request body from a prompt on stdin.

Usage:
    build-body.py <provider> <model> <max_tokens> [reasoning_effort] > body.json

reasoning_effort (optional, OpenAI only): low | medium | high. Sent as the
`reasoning_effort` field; omitted when empty so non-reasoning models keep working.
Set `openai_reasoning_effort` to `off`/`none` in the config to reach the empty case.

Reads prompt from stdin, writes compact JSON to stdout.
"""
import json
import sys


def main() -> int:
    if len(sys.argv) not in (4, 5):
        print("usage: build-body.py <provider> <model> <max_tokens> [reasoning_effort]", file=sys.stderr)
        return 64

    provider, model, max_tokens_s = sys.argv[1:4]
    effort = sys.argv[4] if len(sys.argv) == 5 else ""
    if effort and effort not in ("low", "medium", "high"):
        print(f"reasoning_effort must be low|medium|high, got: {effort!r}", file=sys.stderr)
        return 64
    try:
        max_tokens = int(max_tokens_s)
    except ValueError:
        print(f"max_tokens must be a positive int, got: {max_tokens_s!r}", file=sys.stderr)
        return 64
    if max_tokens <= 0:
        print(f"max_tokens must be a positive int, got: {max_tokens!r}", file=sys.stderr)
        return 64

    prompt = sys.stdin.read()
    if not prompt:
        print("empty prompt on stdin", file=sys.stderr)
        return 64

    if provider == "anthropic":
        body = {
            "model": model,
            "max_tokens": max_tokens,
            "messages": [{"role": "user", "content": prompt}],
        }
    elif provider == "openai":
        body = {
            "model": model,
            "max_completion_tokens": max_tokens,
            "messages": [{"role": "user", "content": prompt}],
        }
        if effort:
            body["reasoning_effort"] = effort
    elif provider == "gemini":
        body = {
            "contents": [{"parts": [{"text": prompt}]}],
            "generationConfig": {"maxOutputTokens": max_tokens},
        }
    else:
        print(f"unknown provider: {provider!r}", file=sys.stderr)
        return 64

    json.dump(body, sys.stdout, separators=(",", ":"), ensure_ascii=False)
    return 0


if __name__ == "__main__":
    sys.exit(main())

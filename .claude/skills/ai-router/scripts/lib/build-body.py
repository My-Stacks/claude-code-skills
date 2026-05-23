#!/usr/bin/env python3
"""Build a provider-specific JSON request body from a prompt on stdin.

Usage:
    build-body.py <provider> <model> <max_tokens> > body.json

Reads prompt from stdin, writes compact JSON to stdout.
"""
import json
import sys


def main() -> int:
    if len(sys.argv) != 4:
        print("usage: build-body.py <provider> <model> <max_tokens>", file=sys.stderr)
        return 64

    provider, model, max_tokens_s = sys.argv[1:]
    try:
        max_tokens = int(max_tokens_s)
    except ValueError:
        print(f"max_tokens must be int, got: {max_tokens_s!r}", file=sys.stderr)
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

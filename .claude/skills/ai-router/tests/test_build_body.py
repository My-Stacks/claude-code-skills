"""build-body.py — provider request bodies.

Covers: per-provider shape, optional OpenAI reasoning_effort (sent only when given,
never for other providers), rejected effort values, max_tokens validation, empty prompt.
"""
import json
import unittest

from _util import run


def body(*args, prompt="hi"):
    rc, out, err = run("build-body.py", lib=True, stdin=prompt, args=list(args))
    return rc, (json.loads(out) if rc == 0 else None), err


class TestBuildBody(unittest.TestCase):
    def test_anthropic_shape_no_sampling_params(self):
        rc, b, _ = body("anthropic", "claude-opus-5", "100")
        self.assertEqual(rc, 0)
        self.assertEqual(b["model"], "claude-opus-5")
        self.assertEqual(b["max_tokens"], 100)
        # Opus 5 rejects temperature/top_p with a 400 — the body must never carry them.
        for k in ("temperature", "top_p", "top_k", "reasoning_effort"):
            self.assertNotIn(k, b)

    def test_openai_effort_sent_when_given(self):
        rc, b, _ = body("openai", "gpt-5.6-sol", "100", "medium")
        self.assertEqual(rc, 0)
        self.assertEqual(b["reasoning_effort"], "medium")
        self.assertEqual(b["max_completion_tokens"], 100)

    def test_openai_effort_omitted_when_empty(self):
        rc, b, _ = body("openai", "gpt-5.6-sol", "100", "")
        self.assertEqual(rc, 0)
        self.assertNotIn("reasoning_effort", b)
        rc, b, _ = body("openai", "gpt-5.6-sol", "100")
        self.assertEqual(rc, 0)
        self.assertNotIn("reasoning_effort", b)

    def test_effort_ignored_for_other_providers(self):
        for prov in ("anthropic", "gemini"):
            rc, b, _ = body(prov, "m", "100", "high")
            self.assertEqual(rc, 0, prov)
            self.assertNotIn("reasoning_effort", json.dumps(b), prov)

    def test_invalid_effort_rejected(self):
        rc, _, err = body("openai", "gpt-5.6-sol", "100", "max")
        self.assertEqual(rc, 64)
        self.assertIn("reasoning_effort", err)

    def test_gemini_shape(self):
        rc, b, _ = body("gemini", "gemini-3.7-flash", "50")
        self.assertEqual(rc, 0)
        self.assertEqual(b["generationConfig"]["maxOutputTokens"], 50)
        self.assertEqual(b["contents"][0]["parts"][0]["text"], "hi")
        self.assertNotIn("model", b)  # model lives in the URL for Gemini

    def test_bad_max_tokens_and_empty_prompt(self):
        self.assertEqual(body("openai", "m", "0")[0], 64)
        self.assertEqual(body("openai", "m", "x")[0], 64)
        self.assertEqual(body("openai", "m", "10", prompt="")[0], 64)


if __name__ == "__main__":
    unittest.main()

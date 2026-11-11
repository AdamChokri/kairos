"""Fixture for kairos.llm-call-unbounded."""

from openai import OpenAI

client = OpenAI(api_key="k", base_url="https://api.deepseek.com")
MESSAGES = [{"role": "user", "content": "hello"}]
NO_THINKING = {"thinking": {"type": "disabled"}}


def vulnerable(model):
    # ruleid: kairos.llm-call-unbounded
    client.chat.completions.create(model=model, messages=MESSAGES)

    # ruleid: kairos.llm-call-unbounded
    client.chat.completions.create(model=model, messages=MESSAGES, timeout=20, max_tokens=400)

    # ruleid: kairos.llm-call-unbounded
    client.chat.completions.create(
        model=model,
        messages=MESSAGES,
        max_tokens=400,
        extra_body={"thinking": {"type": "disabled"}},
    )

    # ruleid: kairos.llm-call-unbounded
    client.chat.completions.create(
        model=model,
        messages=MESSAGES,
        timeout=20,
        extra_body={"thinking": {"type": "disabled"}},
    )

    # ruleid: kairos.llm-call-unbounded
    client.chat.completions.create(
        model=model,
        messages=MESSAGES,
        max_tokens=400,
        timeout=20,
        extra_body={"user_id": "opaque"},
    )


def bounded(model):
    # ok: kairos.llm-call-unbounded
    client.chat.completions.create(
        model=model,
        messages=MESSAGES,
        max_tokens=400,
        timeout=20,
        extra_body={"thinking": {"type": "disabled"}, "user_id": "opaque"},
    )

    # ok: kairos.llm-call-unbounded
    client.chat.completions.create(
        model=model,
        messages=MESSAGES,
        max_tokens=400,
        timeout=20,
        extra_body={"user_id": "opaque", "thinking": {"type": "disabled"}},
    )

    # Not a model call: other methods named create are not this rule's business.
    # ok: kairos.llm-call-unbounded
    MESSAGES.append({"role": "user", "content": "x"})

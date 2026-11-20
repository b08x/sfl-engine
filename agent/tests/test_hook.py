import sys
from types import SimpleNamespace

sys.path.insert(0, ".")

from main import SflGate


class FakeBlock:
    def __init__(self, text):
        self.text = text


class FakeRequest:
    def __init__(self, blocks):
        self.user_content = blocks


async def test_gate_replaces_user_content_with_annotated_prompt():
    hook = SflGate()
    request = FakeRequest([FakeBlock("Can you summarize the revenue report?")])
    outcome = await hook.pre_agent_turn(None, request)
    assert outcome is not None
    blocks = outcome.user_content
    assert len(blocks) == 1
    text = blocks[0].text
    assert text.startswith("=== SFL GATE OUTPUT")
    assert "RAW INPUT: Can you summarize the revenue report?" in text
    assert "Interpersonal: mood=interrogative" in text


async def test_gate_passes_through_non_text_content():
    hook = SflGate()
    request = FakeRequest([SimpleNamespace()])
    assert await hook.pre_agent_turn(None, request) is None


async def test_gate_is_deterministic():
    hook = SflGate()
    request = FakeRequest([FakeBlock("Ship it before Friday.")])
    first = await hook.pre_agent_turn(None, request)
    second = await hook.pre_agent_turn(None, FakeRequest([FakeBlock("Ship it before Friday.")]))
    assert first.user_content[0].text == second.user_content[0].text

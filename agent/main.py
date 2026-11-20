"""The SFL gate agent: a conversational agent behind a deterministic
Systemic Functional Linguistics prompt-engineering gate.

Every user message passes through ``SflGate``, a hook that fires before the
model sees the message. The hook expands and annotates the raw input with the
SFL metafunctions (ideational, interpersonal, textual) using pure, deterministic
Python, and replaces the message with the generated prompt. The functional
agent only ever answers gated prompts.
"""

import asyncio

from mistralai import agents

from sfl_gate import analyze, build_prompt


class SflGate(agents.Hook):
    """Deterministic gate between the user and the functional agent.

    ``pre_agent_turn`` runs once per turn, before the model sees the user's
    message. It never calls a model: the same input always produces the same
    prompt.
    """

    async def pre_agent_turn(self, ctx, request):
        text_blocks = [b for b in request.user_content if getattr(b, "text", None)]
        if not text_blocks:
            return None
        raw = "\n".join(b.text for b in text_blocks)
        prompt = build_prompt(analyze(raw))
        return agents.hook.PreAgentTurnHookContinue(
            user_content=[agents.TextContentBlock(text=prompt)]
        )


agent = agents.Agent(
    model="mistral-large-4",
    name="sfl-gate-agent",
    instructions=(
        "You are the SFL functional agent in a prompt-engineering workflow that uses systemic "
        "functional linguistics. Every message you receive has already passed through a "
        "deterministic SFL gate: the raw user input was expanded and annotated with the "
        "ideational, interpersonal and textual metafunctions, plus the register variables "
        "field, tenor and mode, and the annotation was compiled into the prompt you are reading.\n\n"
        "How to answer:\n"
        "1. Treat the RAW INPUT line as what the user actually said; answer their request.\n"
        "2. Let the annotated metafunctions guide the answer: cover the ideational content "
        "(processes, participants, circumstances), match the interpersonal stance (mood, "
        "modality, appraisal), and follow the textual cues (theme, cohesion).\n"
        "3. End every reply with a short section titled 'SFL reading' that states in two or "
        "three lines which metafunctions the gate surfaced and how they shaped the answer.\n"
        "4. Keep the conversation natural; do not mention the gate mechanics outside the "
        "'SFL reading' section."
    ),
    hooks=[SflGate()],
)


async def demo() -> None:
    result = await agent.run(
        "hey so basically the checkout page is super slow on mobile and customers "
        "keep abandoning carts — can you maybe suggest some quick fixes? we must "
        "ship something before friday"
    )
    print(result.text)


if __name__ == "__main__":
    asyncio.run(demo())

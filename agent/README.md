# SFL Gate Agent

A conversational agent that demonstrates a systemic functional linguistics
(SFL) prompt-engineering workflow, built with the
[Mistral Agents SDK](https://docs.mistral.ai) and deployed on Mistral Cloud as
a managed deployment.

## The workflow

```
raw natural-language input
        |
        v
deterministic SFL gate (pure Python, in a pre_agent_turn hook)
  - expands the input into clauses
  - annotates ideational metafunction: transitivity (process type,
    participants, circumstances)
  - annotates interpersonal metafunction: mood, modality, appraisal
  - annotates textual metafunction: theme/rheme, cohesion, lexical density
  - derives register: field, tenor, mode
        |
        v
generated prompt (sfl_gate/prompt.py)
        |
        v
functional agent (agents.Agent, model-side) answers the gated prompt
```

The gate is a hook (`SflGate` in `main.py`) that runs before the model sees
each user message. It never calls a model, so the same input always produces
the same prompt: the LLM only ever answers annotated, expanded prompts, and
cannot talk its way around the gate.

## Layout

- `main.py` — the agent and the `SflGate` hook.
- `sfl_gate/gate.py` — the deterministic analyzer (lexicons + heuristics).
- `sfl_gate/prompt.py` — compiles the analysis into the functional agent's prompt.
- `webapp/` — a small local FastAPI chat UI that talks to the deployed agent by name.
- `tests/` — pytest suite for the gate, the prompt builder and the hook.

## Run locally

```bash
uv sync
export MISTRAL_API_KEY="..."
uv run agents chat            # chat in the terminal, in-process
uv run pytest                 # run the gate tests
```

## Deploy (managed deployment)

```bash
git push
uv run agents deploy           # builds the pushed commit, runs it Mistral-managed
```

Then chat with the deployed agent by name:

```bash
uv run agents chat sfl-gate-agent
```

or from a program:

```python
agent = agents.Agent.load_from(agent_name="sfl-gate-agent")
result = await agent.run("some raw, disparate input")
```

## Run the webapp

```bash
uv run --env-file .env uvicorn webapp.app:app --port 8000
```

Set `SFL_AGENT_NAME` to talk to a differently named deployment.

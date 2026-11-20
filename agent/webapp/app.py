"""Local chat webapp for the deployed SFL gate agent.

Run it with your Mistral API key, pointing at the deployed agent by name:

    uv run --env-file .env uvicorn webapp.app:app --port 8000

The webapp is a thin client: every turn runs on the managed deployment, and
the deterministic SFL gate runs inside the agent, so the UI always sends raw
natural language.
"""

import os
from pathlib import Path

from fastapi import FastAPI
from fastapi.responses import FileResponse
from pydantic import BaseModel

from mistralai import agents

AGENT_NAME = os.environ.get("SFL_AGENT_NAME", "sfl-gate-agent")

app = FastAPI(title="SFL gate agent")

STATIC_DIR = Path(__file__).parent / "static"

_agent: agents.Agent | None = None


def get_agent() -> agents.Agent:
    global _agent
    if _agent is None:
        _agent = agents.Agent.load_from(agent_name=AGENT_NAME)
    return _agent


class ChatIn(BaseModel):
    message: str
    session_id: str | None = None


class ChatOut(BaseModel):
    session_id: str
    reply: str


@app.get("/")
async def index() -> FileResponse:
    return FileResponse(STATIC_DIR / "index.html")


@app.post("/chat", response_model=ChatOut)
async def chat(body: ChatIn) -> ChatOut:
    agent = get_agent()
    if body.session_id:
        session = agent.session(body.session_id)
    else:
        session = await agent.start_session()
    state = await session.run(body.message)
    if isinstance(state, agents.Busy):
        state = await state.turn.result()
    if isinstance(state, agents.Completed):
        reply = state.text
    elif isinstance(state, agents.Failed):
        reply = f"Turn failed: {state.error.code}."
    else:
        reply = "The turn did not complete."
    return ChatOut(session_id=session.session_id, reply=reply)

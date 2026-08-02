#!/usr/bin/env python3
"""NDJSON sidecar for spaCy Pass 1 parsing.

Replaces the legacy PyCall-in-process architecture (D1: the GC.start hack,
GIL/GVL deadlock risk, the Sidekiq `-c 1` concurrency ceiling) with a plain
subprocess boundary: the Ruby process never touches the Python interpreter
directly, it only writes/reads JSON lines on this process's stdin/stdout.

Protocol (one JSON object per line, always flushed immediately):
  startup ->            {"type": "ready", "model": "<name>"}
  request (stdin)  ->   {"id": "<uuid>", "text": "<str>", "document_id": "<str>|null}
  response (stdout) ->  {"id": "<uuid>", "clauses": [...]}
                     or  {"id": "<uuid>"|null, "error": "<message>"}

Positional head-index resolution -- not a text lookup -- is the whole
point of this rewrite (fixes F1/D1): `token.head.i - sent.start`
addresses a token's head by its position in the sentence, so two
identical words ("the", "the") never collapse onto the same head_index
the way the legacy PyCall code's text-keyed hash did.
"""
import argparse
import json
import sys
import uuid


def build_clause(sent, sentence_index, document_id):
    tokens = []
    for local_i, token in enumerate(sent):
        if not token.text.strip():
            continue
        head_index = -1 if token.head.i == token.i else token.head.i - sent.start
        tokens.append({
            "text": token.text,
            "lemma": token.lemma_ or token.text.lower(),
            "pos": token.pos_ or "X",
            "tag": token.tag_ or "X",
            "dep": token.dep_ or "dep",
            "head_index": head_index,
            "morphology": token.morph.to_dict(),
            "index": local_i,
        })

    if not tokens:
        return None

    root_index = next((i for i, t in enumerate(tokens) if t["dep"] == "ROOT"), 0)
    return {
        "id": str(uuid.uuid4()),
        "text": sent.text.strip(),
        "tokens": tokens,
        "root_index": root_index,
        "sentence_index": sentence_index,
        "document_id": document_id,
    }


def parse_text(nlp, text, document_id):
    if not text or not text.strip():
        return []

    doc = nlp(text)
    clauses = []
    sentence_index = 0
    for sent in doc.sents:
        if not sent.text.strip():
            continue
        clause = build_clause(sent, sentence_index, document_id)
        if clause is None:
            continue
        clauses.append(clause)
        sentence_index += 1
    return clauses


def emit(payload):
    sys.stdout.write(json.dumps(payload) + "\n")
    sys.stdout.flush()


def main():
    argparser = argparse.ArgumentParser()
    argparser.add_argument("--model", default="en_core_web_sm")
    args = argparser.parse_args()

    import spacy
    nlp = spacy.load(args.model)

    emit({"type": "ready", "model": args.model})

    try:
        for line in sys.stdin:
            line = line.strip()
            if not line:
                continue

            request_id = None
            try:
                request = json.loads(line)
                request_id = request.get("id")
                clauses = parse_text(nlp, request.get("text", ""), request.get("document_id"))
                emit({"id": request_id, "clauses": clauses})
            except Exception as exc:  # a malformed/unparseable request must not crash the server
                emit({"id": request_id, "error": str(exc)})
    except KeyboardInterrupt:
        # Caller (SpacySidecarParser) closes our stdin/stdout to shut us down;
        # a stray SIGINT reaching us directly (e.g. no process-group isolation)
        # should still exit quietly rather than an unhandled traceback.
        pass


if __name__ == "__main__":
    main()

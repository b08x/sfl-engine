#!/usr/bin/env python3
"""NDJSON sidecar for BERTopic topic modelling.

A pure computation service: the caller supplies the texts and their
embeddings in each request. This process loads no embedding model, reads no
environment variables and makes no network calls at runtime. A subprocess
boundary keeps the Ruby process out of the Python interpreter, the same way
the spaCy sidecar does.

Protocol (one JSON object per line, always flushed immediately):
  startup ->            {"type": "ready", "model": "bertopic"}
  request (stdin)  ->   {"id": "<str>", "type": "bertopic",
                         "texts": ["<str>", ...],
                         "embeddings": [[<float>, ...], ...],
                         "nr_topics": <int> | null,
                         "min_topic_size": <int>,
                         "seed": <int>}
  response (stdout) ->  {"id": "<str>", "topics": [<int>, ...],
                         "topic_words": {"<topic id>": ["<word>", ...]},
                         "outlier_topic": -1}
                     or  {"id": "<str>"|null, "error": "<message>"}

"topics" holds one entry per input text, in input order. Outlier turns are
-1. "topic_words" maps each non-outlier topic id (as a string key) to its
top words. A nr_topics of null lets BERTopic choose the topic count.

Determinism: UMAP is seeded from the request's "seed", and HDBSCAN is
deterministic, so an identical request yields identical topics.
"""
import argparse
import json
import sys

MODEL_NAME = "bertopic"
OUTLIER_TOPIC = -1
TOP_WORDS = 10


def validate(request):
    texts = request.get("texts")
    embeddings = request.get("embeddings")

    if not isinstance(texts, list) or not all(isinstance(t, str) for t in texts):
        raise ValueError("texts must be a list of strings")
    if not isinstance(embeddings, list):
        raise ValueError("embeddings must be a list of vectors")
    if len(texts) != len(embeddings):
        raise ValueError(
            f"texts and embeddings lengths differ: {len(texts)} != {len(embeddings)}"
        )
    if len(texts) < 2:
        raise ValueError("at least 2 texts are required")

    dimension = None
    for vector in embeddings:
        if not isinstance(vector, list) or not all(
            isinstance(x, (int, float)) and not isinstance(x, bool) for x in vector
        ):
            raise ValueError("every embedding must be a list of numbers")
        if dimension is None:
            dimension = len(vector)
        elif len(vector) != dimension:
            raise ValueError("all embeddings must have the same dimension")
    if not dimension:
        raise ValueError("embeddings must have at least one dimension")

    min_topic_size = request.get("min_topic_size")
    if not isinstance(min_topic_size, int) or isinstance(min_topic_size, bool) or min_topic_size < 2:
        raise ValueError("min_topic_size must be an integer >= 2")

    seed = request.get("seed")
    if not isinstance(seed, int) or isinstance(seed, bool):
        raise ValueError("seed must be an integer")

    nr_topics = request.get("nr_topics")
    if nr_topics is not None and (
        not isinstance(nr_topics, int) or isinstance(nr_topics, bool) or nr_topics < 1
    ):
        raise ValueError("nr_topics must be null or an integer >= 1")

    return texts, embeddings, nr_topics, min_topic_size, seed


def build_model(nr_topics, min_topic_size, seed, n_samples):
    from bertopic import BERTopic
    from umap import UMAP

    umap_model = UMAP(
        n_neighbors=min(15, n_samples - 1),
        n_components=min(5, max(2, n_samples - 2)),
        metric="cosine",
        random_state=seed,
    )
    return BERTopic(
        embedding_model=None,
        umap_model=umap_model,
        min_topic_size=min_topic_size,
        nr_topics=nr_topics,
        verbose=False,
    )


def cluster(request):
    texts, embeddings, nr_topics, min_topic_size, seed = validate(request)

    import numpy as np

    matrix = np.asarray(embeddings, dtype=np.float32)

    model = build_model(nr_topics, min_topic_size, seed, len(texts))
    topics, _ = model.fit_transform(texts, matrix)

    topics = [int(t) for t in topics]
    topic_words = {}
    for topic_id in sorted(set(topics)):
        if topic_id == OUTLIER_TOPIC:
            continue
        words = model.get_topic(topic_id) or []
        topic_words[str(topic_id)] = [word for word, _score in words[:TOP_WORDS]]

    return {
        "id": request["id"],
        "topics": topics,
        "topic_words": topic_words,
        "outlier_topic": OUTLIER_TOPIC,
    }


def emit(payload):
    sys.stdout.write(json.dumps(payload) + "\n")
    sys.stdout.flush()


def main():
    argparse.ArgumentParser(description=__doc__.splitlines()[0]).parse_args()

    # Import here so a missing dependency fails at startup, before "ready".
    import bertopic  # noqa: F401

    emit({"type": "ready", "model": MODEL_NAME})

    try:
        for line in sys.stdin:
            line = line.strip()
            if not line:
                continue

            request_id = None
            try:
                request = json.loads(line)
                request_id = request.get("id")
                if request.get("type") != MODEL_NAME:
                    raise ValueError(f"unsupported request type: {request.get('type')!r}")
                if not isinstance(request_id, str):
                    raise ValueError("id must be a string")
                emit(cluster(request))
            except Exception as exc:  # a malformed request must not crash the server
                emit({"id": request_id, "error": str(exc)})
    except KeyboardInterrupt:
        # Caller closes stdin/stdout to shut us down; exit quietly on a stray SIGINT.
        pass


if __name__ == "__main__":
    main()

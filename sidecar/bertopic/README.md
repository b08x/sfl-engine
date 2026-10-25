# BERTopic sidecar

A line-delimited JSON service that runs BERTopic topic modelling. The caller
sends texts with their precomputed embeddings; the service returns a topic id
for each text and the top words for each topic.

The service is pure computation. It loads no embedding model, reads no
environment variables and makes no network calls at runtime.

## Protocol

Startup writes one line:

```json
{"type": "ready", "model": "bertopic"}
```

Request (one line on stdin):

```json
{"id": "req-1", "type": "bertopic", "texts": ["..."], "embeddings": [[0.1, 0.2]],
 "nr_topics": null, "min_topic_size": 3, "seed": 42}
```

- `texts` and `embeddings` have the same length, and at least 2 entries.
- Every embedding has the same dimension.
- `nr_topics` is `null` to let BERTopic choose the topic count, or an integer.
- `seed` seeds UMAP, so an identical request gives identical topics.

Response (one line on stdout):

```json
{"id": "req-1", "topics": [0, 0, -1, 1], "topic_words": {"0": ["..."], "1": ["..."]}, "outlier_topic": -1}
```

`topics` has one entry per input text, in order. `-1` marks outlier turns.

Errors return `{"id": <id or null>, "error": "<message>"}` and do not stop the
process.

## Run

```sh
python3 sidecar/bertopic/bertopic_sidecar.py
```

Dependencies are pinned in `requirements.txt`. The Docker image is built from
this directory:

```sh
docker build -t sfl-bertopic-sidecar sidecar/bertopic
docker run -i --rm sfl-bertopic-sidecar
```

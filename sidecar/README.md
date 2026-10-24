# sidecar/

Pass 1 (syntactic parsing) moved out of the Ruby process entirely (track
decision 2), eliminating the legacy PyCall-in-process hazards: the
`GC.start` workaround, GIL/GVL deadlock risk, and the Sidekiq `-c 1`
concurrency ceiling that in-process PyCall forced. `SFL::Core::PassOne::SpacySidecarParser`
talks to this subprocess over a line-delimited JSON protocol on
stdin/stdout — see the docstring in `spacy_sidecar.py` for the exact
message shapes.

**Note on the containerized API (issue #34):** `docker/api.Dockerfile`
bakes spaCy directly into the `sfl-api` image's system Python (mirroring
this directory's own `pip install spacy && spacy download` approach)
rather than running this directory's `Dockerfile` as a *separate*
sidecar container per compile call — that would require the API
container to itself have Docker access just to `docker run` it, the
same wrong shape #17/#18 already fixed for
`DockerServices.ensure_running!`. This directory's `Dockerfile` is kept
as-is, not deleted: it's still a valid, working reference for anyone
running Pass 1 as a genuinely separate process outside the `sfl-api`
image (see "Running it via Docker" below).

## Running it directly (local dev)

Requires `python3` with `spacy` installed and a model downloaded:

```shell
pip install spacy
python3 -m spacy download en_core_web_sm
```

`SFL::Core::PassOne::SpacySidecarParser.new(model: "en_core_web_sm")` defaults to
`["python3", "sidecar/spacy_sidecar.py", "--model", model]`. The model is
resolved at boot from the `SPACY_MODEL` env var, falling back to
`en_core_web_sm` (`SFL::Boot::DEFAULT_SPACY_MODEL`) — and
`spacy_sidecar.py`'s own `--model` default is `en_core_web_sm` too. So the
local-dev path still runs `sm` unless you say otherwise.

## Running it via Docker

The image downloads `en_core_web_md` at build time and bakes it into its
`CMD`, so the Docker default is `md` — a bare
`docker run -i --rm sfl-spacy-sidecar` runs it with no further arguments.
(This differs from the local-dev default above: the *script's* `--model`
default is `sm`, but the Dockerfile's `CMD` overrides it with `md`. An
explicit `--model` must name a model the image actually downloaded.)

`bin/build-sidecar` builds the image and smoke-tests it over the sidecar's
real NDJSON protocol — `--model` defaults to the model parsed from the
Dockerfile's download line, `--tag` to `sfl-spacy-sidecar`; `--no-smoke`
and `--no-cache` do what they say. On success it prints the parser
construction snippet. Or build by hand:

```shell
docker build -t sfl-spacy-sidecar sidecar/
```

Then construct the parser with an explicit command, e.g.:

```ruby
SFL::Core::PassOne::SpacySidecarParser.new(
  model: "en_core_web_md",
  command: ["docker", "run", "-i", "--rm", "sfl-spacy-sidecar", "--model", "en_core_web_md"]
)
```

Same NDJSON stdio protocol either way — the parser doesn't know or care
which transport launched the process.

## Head-index fix (F1/D1)

The legacy in-process implementation resolved a token's head by looking
up `local_idx[token.head.text]`, a **text**-keyed hash — so on a
sentence with a repeated word, every duplicate's dependents resolved to
the *first* occurrence of that word rather than the correct one. This
sidecar computes `token.head.i - sent.start` instead: spaCy's native
positional token index, offset to be sentence-local. No text lookup
exists in this codepath, so the bug class is structurally impossible.

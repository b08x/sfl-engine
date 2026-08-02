# SFL API service image (issue #34) — bakes spaCy into the image's system
# Python instead of running it as a separate sibling container.
#
# Why baked in, not sidecar/Dockerfile as a second container per compile
# call: that would require this image to itself have Docker access
# (socket-mount) just to `docker run` the sidecar, the same wrong shape
# blockers #17/#18 already fixed for `DockerServices.ensure_running!`.
# `Boot.resolve_pass1_command` returns nil (and SpacySidecarParser falls
# back to bare `python3` + sidecar/spacy_sidecar.py) whenever
# .sfl-python/interpreter_path doesn't exist — which it never will in a
# fresh image build — so an image with `python3` + spaCy on the default
# system PATH needs zero Ruby-side changes to work. bin/setup-python's
# uv-vendoring exists to solve a different problem (diverse,
# non-containerized host machines) that doesn't apply inside an image the
# team fully controls.
#
# Mirrors sidecar/Dockerfile's own simple `pip install spacy~=3.8 && spacy
# download en_core_web_sm` approach rather than reusing bin/setup-python.
# sidecar/Dockerfile itself is kept as-is (not deleted) — it's still a
# valid standalone reference for anyone running Pass 1 as a genuinely
# separate process outside this image.
FROM ruby:4.0.1-slim

RUN apt-get update -qq \
  && apt-get install -y --no-install-recommends build-essential libpq-dev python3 python3-pip \
  && rm -rf /var/lib/apt/lists/*

# PIP_BREAK_SYSTEM_PACKAGES=1 (not just a one-off --break-system-packages flag): live-verified
# 2026-08-02 that `spacy download` shells out to a SECOND, internal `pip install` for the model
# wheel that doesn't inherit CLI flags from the first command -- only the env var reaches it.
# click explicit: this spacy~=3.8's resolved dependency set (typer 0.27.0) doesn't pull it in
# transitively, and `spacy download` hard-imports it at spacy/cli/_util.py load time.
ENV PIP_BREAK_SYSTEM_PACKAGES=1
RUN pip install --no-cache-dir spacy~=3.8 click \
  && python3 -m spacy download en_core_web_sm

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY . .

EXPOSE 3001
ENV HOST=0.0.0.0
ENV PORT=3001

# NOT `bundle exec sfl-api` -- live-verified 2026-08-02 that it fails with "command not found:
# sfl-api" on this app's own documented host setup too (AGENTS.md's own "bundle exec sfl-api"
# is stale): this is a non-gem application (track decision 1, no gemspec), so there is no
# `executables` list for Bundler's binstub resolution to find "sfl-api" in. `exe/sfl-api` is a
# real, directly-executable file; running it by path works with no binstub involved.
CMD ["bundle", "exec", "exe/sfl-api"]

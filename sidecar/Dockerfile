# Pass 1 spaCy sidecar. Built once, run per-parse-session via
# `docker run -i --rm sfl-spacy-sidecar [--model <name>]` — stdin/stdout
# carry the same NDJSON protocol spacy_sidecar.py speaks when invoked
# directly with a local `python3`, so SFL::Core::PassOne::SpacySidecarParser
# doesn't need to know or care which transport launched it.
FROM python:3.12-slim

WORKDIR /sidecar

RUN pip install --no-cache-dir spacy~=3.8 \
    && python -m spacy download en_core_web_sm

COPY spacy_sidecar.py .

ENTRYPOINT ["python", "spacy_sidecar.py"]
CMD ["--model", "en_core_web_sm"]

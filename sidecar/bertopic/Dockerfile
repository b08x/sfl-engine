FROM python:3.12-slim

WORKDIR /sidecar

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# No model is downloaded at build time; embeddings arrive in each request.
COPY bertopic_sidecar.py .

ENTRYPOINT ["python", "bertopic_sidecar.py"]

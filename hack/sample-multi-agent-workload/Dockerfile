FROM python:3.12-slim@sha256:5e2bdb1b0d542d5039cffb8181c65930093949194a65c365dfb1b0fe13a4fa5b
ARG PIP_INDEX_URL=https://pypi.org/simple
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 \
    SAMPLE_DATABASE=/app/data/retail.db
WORKDIR /app
COPY requirements.lock ./
RUN python -m pip install --no-cache-dir -r requirements.lock
COPY pyproject.toml ./
COPY src ./src
RUN python -m pip install --no-cache-dir --no-deps . \
    && python -m sample_workload initialize --database /app/data/retail.db --seed 42
USER 10001:10001
EXPOSE 8080
CMD ["python", "-m", "sample_workload.container"]

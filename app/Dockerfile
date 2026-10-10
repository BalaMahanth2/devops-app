# syntax=docker/dockerfile:1

ARG PYTHON_VERSION=3.14

# stage 1: builder - install dependencies
FROM python:${PYTHON_VERSION}-slim AS builder

WORKDIR /build

# The venv gets no pip of its own. The builder's pip installs into it.
RUN python -m venv --without-pip /opt/venv

COPY requirements.txt .
RUN pip --python /opt/venv/bin/python install --no-cache-dir -r requirements.txt

# stage 2: runtime - only what is needed to run
FROM python:${PYTHON_VERSION}-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/opt/venv/bin:$PATH"

# pip is a build tool. Remove it from the runtime image.
RUN pip uninstall --yes pip \
    && useradd --uid 10001 --no-create-home --shell /usr/sbin/nologin appuser

COPY --from=builder /opt/venv /opt/venv

WORKDIR /app

COPY src/ .

USER 10001

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8080/health', timeout=2)"]

ARG APP_VERSION=dev
ENV APP_VERSION=${APP_VERSION}

CMD ["gunicorn", "--no-control-socket", "--bind", "0.0.0.0:8080", "--workers", "2", "--access-logfile", "-", "main:app"]

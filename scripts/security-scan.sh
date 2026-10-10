#!/usr/bin/env bash
# Runs the security scanners in pinned containers.
# The same script runs on a laptop and in CI, so the results match.
#
# Usage: scripts/security-scan.sh [secrets|dockerfile|config|deps|image|all]
set -euo pipefail

# Git Bash on Windows rewrites arguments that look like Unix paths. Switch that off.
export MSYS_NO_PATHCONV=1

# Pinned by version AND digest: a tag can be moved, a digest cannot.
GITLEAKS_IMAGE="ghcr.io/gitleaks/gitleaks:v8.30.1@sha256:c00b6bd0aeb3071cbcb79009cb16a60dd9e0a7c60e2be9ab65d25e6bc8abbb7f"
HADOLINT_IMAGE="hadolint/hadolint:v2.15.1@sha256:32dac94127fd60b7b7e3fbfc65e1383b9b5e25c9bfd7b8536de7a539fe68a12d"
TRIVY_IMAGE="aquasec/trivy:0.75.0@sha256:af6acf9a6b85dfe389a1941505c0ce9efef52a4719635e1a962f022a3d855daa"

cd "$(dirname "$0")/.."
# Docker needs a real host path. On Git Bash "pwd -W" gives the Windows form
# (C:/...); on Linux that option does not exist, so plain "pwd" is used.
ROOT="$(pwd -W 2>/dev/null || pwd)"
SCAN_IMAGE="${SCAN_IMAGE:-devops-app:scan}"

trap 'rm -rf "$ROOT/.scan"' EXIT

# The repo is mounted read-only, and the Docker socket is never shared.
trivy() {
  docker run --rm \
    -v trivy-cache:/root/.cache/trivy \
    -v "$ROOT:/src:ro" \
    "$TRIVY_IMAGE" "$@" --ignorefile /src/security/.trivyignore
}

scan_secrets() {
  echo "==> Gitleaks: secrets anywhere in git history"
  docker run --rm -v "$ROOT:/repo:ro" "$GITLEAKS_IMAGE" \
    git --no-banner --redact --verbose /repo
}

scan_dockerfile() {
  echo "==> Hadolint: Dockerfile best practices"
  docker run --rm -i "$HADOLINT_IMAGE" < app/Dockerfile
}

scan_config() {
  echo "==> Trivy: Dockerfile misconfigurations"
  trivy config --quiet --exit-code 1 /src/app
}

scan_deps() {
  echo "==> Trivy: known vulnerabilities in dependencies"
  trivy fs --quiet --scanners vuln --severity HIGH,CRITICAL --exit-code 1 /src/app
}

scan_image() {
  echo "==> Trivy: known vulnerabilities in the built image"
  if [ -z "${SKIP_BUILD:-}" ]; then
    docker build --quiet -t "$SCAN_IMAGE" app
  fi
  mkdir -p .scan
  docker save "$SCAN_IMAGE" > .scan/image.tar
  trivy image --quiet --input /src/.scan/image.tar \
    --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1
}

case "${1:-all}" in
  secrets)    scan_secrets ;;
  dockerfile) scan_dockerfile ;;
  config)     scan_config ;;
  deps)       scan_deps ;;
  image)      scan_image ;;
  all)
    failed=""
    for scan in secrets dockerfile config deps image; do
      "scan_$scan" || failed="$failed $scan"
    done
    if [ -n "$failed" ]; then
      echo "==> FAILED:$failed"
      exit 1
    fi
    ;;
  *)
    echo "Usage: $0 [secrets|dockerfile|config|deps|image|all]" >&2
    exit 2
    ;;
esac

echo "==> Passed"

#!/bin/bash
# Lint tests: helm lint, template rendering checks.
# No cluster required.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="${SCRIPT_DIR}/../.."
TESTS_DIR="${SCRIPT_DIR}/.."

PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

echo "=== Lint: helm lint (default values) ==="
if helm lint "${CHART_DIR}" --quiet; then
  pass "helm lint with default values"
else
  fail "helm lint with default values"
fi

echo ""
echo "=== Lint: helm lint (test values) ==="
if helm lint "${CHART_DIR}" -f "${TESTS_DIR}/values-test.yaml" --quiet; then
  pass "helm lint with test values"
else
  fail "helm lint with test values"
fi

echo ""
echo "=== Lint: helm lint (minimal values) ==="
if helm lint "${CHART_DIR}" -f "${CHART_DIR}/examples/values-minimal.yaml" --quiet; then
  pass "helm lint with minimal example values"
else
  fail "helm lint with minimal example values"
fi

echo ""
echo "=== Lint: helm lint (full values) ==="
if helm lint "${CHART_DIR}" -f "${CHART_DIR}/examples/values-full.yaml" --quiet; then
  pass "helm lint with full example values"
else
  fail "helm lint with full example values"
fi

echo ""
echo "=== Lint: template rendering (test values) ==="
if helm template arrmada-test "${CHART_DIR}" -f "${TESTS_DIR}/values-test.yaml" > /dev/null 2>&1; then
  pass "helm template renders without errors"
else
  fail "helm template rendered with errors"
fi

echo ""
echo "=== Lint: sonarr disabled ==="
if helm template arrmada-test "${CHART_DIR}" \
  -f "${TESTS_DIR}/values-test.yaml" \
  --set sonarr.enabled=false > /dev/null 2>&1; then
  pass "helm template with sonarr disabled"
else
  fail "helm template with sonarr disabled"
fi

echo ""
echo "=== Lint: configSync disabled ==="
if helm template arrmada-test "${CHART_DIR}" \
  -f "${TESTS_DIR}/values-test.yaml" \
  --set configSync.enabled=false > /dev/null 2>&1; then
  pass "helm template with configSync disabled"
else
  fail "helm template with configSync disabled"
fi

echo ""
echo "=== Lint: schema validation (invalid API key rejected) ==="
if helm template arrmada-test "${CHART_DIR}" \
  -f "${TESTS_DIR}/values-test.yaml" \
  --set global.apiKeys.sonarr=invalid-key > /dev/null 2>&1; then
  fail "schema should reject invalid API key"
else
  pass "schema correctly rejects invalid API key"
fi

echo ""

if [[ "${FAIL}" -gt 0 ]]; then
  echo "RESULT: ${PASS} passed, ${FAIL} failed"
  exit 1
fi
echo "RESULT: ${PASS} passed, 0 failed — all lint checks OK"

## Arrmada test runner
## Run from this directory: make lint / make unit / make integration
## Or from repo root:       make -C tests lint
##
## CI/CD: set KUBECONFIG before calling make, or pre-create tests/.kubeconfig.
## Local: run `make setup` to create a k3d cluster if no kubeconfig exists.

KUBECONFIG  := $(shell pwd)/.kubeconfig
K3D_CLUSTER := arrmada-test
NAMESPACE   := arrmada-test

export KUBECONFIG

.PHONY: all lint unit integration setup teardown clean

all: lint unit

## ── Lint (no cluster required) ───────────────────────────────────────────────
lint:
	./lint/lint.sh

## ── Unit tests (no cluster required, requires helm-unittest plugin) ──────────
unit:
	helm unittest ../ -f 'tests/unit/*_test.yaml'

## ── Integration tests ────────────────────────────────────────────────────────
## Uses existing tests/.kubeconfig if present; otherwise calls setup to create
## a k3d cluster first.
integration: setup
	./integration/run.sh

## ── Cluster lifecycle ────────────────────────────────────────────────────────
## setup: no-op if tests/.kubeconfig already exists (CI or pre-provisioned).
##        Creates a k3d cluster and writes the kubeconfig otherwise (local dev).
setup:
	./setup.sh

teardown:
	k3d cluster delete $(K3D_CLUSTER)
	rm -f $(KUBECONFIG)

clean: teardown

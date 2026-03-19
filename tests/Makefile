## Arrmada test runner
## Run from this directory: make lint / make unit / make integration
## Or from repo root:       make -C tests lint

KUBECONFIG  := $(shell pwd)/.kubeconfig.yml
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

## ── Integration tests (requires k3d cluster) ─────────────────────────────────
integration: setup
	./integration/run.sh

## ── Cluster lifecycle ────────────────────────────────────────────────────────
setup:
	@if ! k3d cluster list 2>/dev/null | grep -q $(K3D_CLUSTER); then \
		k3d cluster create --config k3d-cluster.yaml; \
	else \
		echo "Cluster $(K3D_CLUSTER) already exists"; \
	fi
	k3d kubeconfig get $(K3D_CLUSTER) > $(KUBECONFIG)
	@echo "Kubeconfig written to $(KUBECONFIG)"

teardown:
	k3d cluster delete $(K3D_CLUSTER)
	rm -f $(KUBECONFIG)

clean: teardown

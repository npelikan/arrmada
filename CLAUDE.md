# Arrmada

Unified Helm chart for the *arr media automation stack (Sonarr, Radarr, Prowlarr).

## Project Overview

Arrmada is a single Helm chart that deploys and **declaratively configures** the entire *arr stack on Kubernetes. Unlike typical Helm charts that only deploy containers, Arrmada manages the full application configuration lifecycle: quality profiles, custom formats, download clients, indexers, media naming, root folders, and more -- all defined as Helm values.

### Core Services

| Service  | Purpose                  | Default Port | API Version |
|----------|--------------------------|--------------|-------------|
| Sonarr   | TV series management     | 8989         | v3          |
| Radarr   | Movie management         | 7878         | v3          |
| Prowlarr | Indexer management/proxy | 9696         | v1          |

### Key Design Principles

1. **Fully declarative**: All application configuration is defined in `values.yaml` and synced via APIs on startup and schedule
2. **PostgreSQL-backed**: Sonarr and Radarr use external PostgreSQL (not embedded SQLite). Prowlarr uses PostgreSQL when available, SQLite as fallback
3. **TRaSH Guide integration**: Recyclarr runs as a sidecar/CronJob to sync community-vetted quality profiles and custom formats
4. **External DB assumption**: PostgreSQL is provisioned outside this chart (different clusters use different PG operators). The chart accepts connection parameters only
5. **Prowlarr as indexer hub**: Prowlarr manages indexers centrally and syncs them to Sonarr/Radarr via its application sync feature
6. **Sensitive indexer config via Secrets**: Prowlarr indexer definitions (which contain credentials) are provided as Kubernetes Secrets, not inline values

## Architecture

```
                    ┌─────────────┐
                    │  Prowlarr   │──── Indexer sync ────┐
                    │  (indexers) │                       │
                    └──────┬──────┘                       │
                           │                              │
                    ┌──────┴──────┐              ┌───────┴───────┐
                    │   Sonarr    │              │    Radarr     │
                    │   (TV)      │              │   (Movies)    │
                    └──────┬──────┘              └───────┬───────┘
                           │                             │
                    ┌──────┴─────────────────────────────┴──────┐
                    │          External PostgreSQL               │
                    │  (sonarr-main, sonarr-log,                │
                    │   radarr-main, radarr-log,                │
                    │   prowlarr-main, prowlarr-log)            │
                    └───────────────────────────────────────────┘

    ┌──────────────┐
    │  Recyclarr   │──── TRaSH Guide sync ──── Sonarr + Radarr
    │  (CronJob)   │
    └──────────────┘

    ┌──────────────┐
    │  Config Init │──── API-based config sync on deploy
    │  (Job/Hook)  │     (quality profiles, download clients,
    └──────────────┘      root folders, notifications, tags, etc.)
```

## Repository Structure

```
arrmada/
├── CLAUDE.md                  # This file
├── README.md                  # User-facing documentation
├── LICENSE                    # Unlicense
├── Chart.yaml                 # Helm chart metadata
├── values.yaml                # Default values with full config schema
├── values.schema.json         # JSON Schema for values validation
├── templates/
│   ├── _helpers.tpl           # Template helpers and naming conventions
│   ├── NOTES.txt              # Post-install instructions
│   │
│   ├── # Per-service templates
│   ├── sonarr/
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   ├── ingress.yaml
│   │   ├── configmap.yaml     # config.xml generation (postgres, API key, urlBase)
│   │   └── pvc.yaml
│   ├── radarr/
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   ├── ingress.yaml
│   │   ├── configmap.yaml
│   │   └── pvc.yaml
│   ├── prowlarr/
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   ├── ingress.yaml
│   │   ├── configmap.yaml
│   │   └── pvc.yaml
│   │
│   ├── # Configuration management
│   ├── config/
│   │   ├── configjob.yaml     # Post-install/upgrade Job for declarative config sync
│   │   ├── configmap.yaml     # Config sync scripts and desired-state YAML
│   │   └── cronjob.yaml       # Periodic config drift reconciliation (optional)
│   │
│   ├── # Recyclarr
│   ├── recyclarr/
│   │   ├── configmap.yaml     # recyclarr.yml from values
│   │   └── cronjob.yaml       # Scheduled TRaSH guide sync
│   │
│   └── # Shared
│       └── serviceaccount.yaml
│
├── scripts/
│   ├── config-sync.sh         # Main config sync entrypoint
│   ├── wait-for-api.sh        # Wait for *arr API readiness
│   └── prowlarr-export.sh     # Helper: export prowlarr indexer config to YAML
│
├── examples/
│   ├── values-minimal.yaml    # Minimal deployment (just services, no config)
│   ├── values-full.yaml       # Full declarative config example
│   └── prowlarr-indexers-secret.yaml  # Example indexer secret
│
└── docs/
    └── prowlarr-indexers.md   # Guide: extracting indexer config from local Prowlarr
```

## Technology Stack

- **Helm 3**: Chart packaging and templating
- **Container images**: `ghcr.io/hotio/sonarr`, `ghcr.io/hotio/radarr`, `ghcr.io/hotio/prowlarr`
- **Recyclarr**: `ghcr.io/recyclarr/recyclarr` (TRaSH guide sync)
- **Config sync**: Custom shell scripts using `curl` + `jq` running in alpine-based init container
- **PostgreSQL**: External, user-provided (connection string in values/secrets)

## Configuration Sync Strategy

The chart implements a **convergent desired-state** configuration model inspired by Buildarr:

1. **Init container** (`wait-for-api.sh`): Blocks until the *arr API responds on `/api/v{N}/system/status`
2. **Post-install/upgrade Job** (`config-sync.sh`): Reads desired state from ConfigMap, fetches current state from API, and applies diffs:
   - `GET` current resources → compare with desired → `POST` new / `PUT` changed / optionally `DELETE` unmanaged
3. **CronJob** (optional): Periodic reconciliation to catch manual UI changes
4. **Recyclarr CronJob**: Syncs TRaSH guide profiles on schedule

### API Key Bootstrap

On first deploy, the init container generates `config.xml` with a pre-defined API key (from a Kubernetes Secret). This ensures the config sync Job can authenticate immediately without manual intervention.

### Managed Resource Types

| Resource            | Sonarr | Radarr | Prowlarr | Notes                                    |
|---------------------|--------|--------|----------|------------------------------------------|
| Root Folders        | Yes    | Yes    | --       | Media library paths                      |
| Quality Profiles    | Yes    | Yes    | --       | Also managed by Recyclarr for TRaSH      |
| Quality Definitions | Yes    | Yes    | --       | File size ranges per quality              |
| Custom Formats      | Yes    | Yes    | --       | Also managed by Recyclarr for TRaSH      |
| Delay Profiles      | Yes    | Yes    | --       |                                          |
| Download Clients    | Yes    | Yes    | Yes      | Transmission, SABnzbd, NZBGet, etc.      |
| Indexers            | --     | --     | Yes      | Managed centrally, synced to apps         |
| Applications        | --     | --     | Yes      | Prowlarr→Sonarr/Radarr connections       |
| Media Naming        | Yes    | Yes    | --       | Episode/movie/folder naming patterns      |
| Media Management    | Yes    | Yes    | --       | File handling, permissions                |
| Notifications       | Yes    | Yes    | Yes      | Webhooks, email, Telegram, etc.           |
| Tags                | Yes    | Yes    | Yes      |                                          |
| Import Lists        | Yes    | Yes    | --       |                                          |
| UI Settings         | Yes    | Yes    | Yes      | Theme, language, date format              |
| General Settings    | Yes    | Yes    | Yes      | Auth, logging, analytics, proxy           |

## Implementation Plan

The full implementation plan is in `PLAN.md` (gitignored). It defines 10 sequential phases, each producing a working chart. Refer to it for phase goals, file lists, key details, and verification steps.

## Workflow Rules

- **Commit on every turn**: This project uses roborev for code review. Create a commit at the end of every turn of work so changes can be reviewed incrementally.
- **Development branch**: All work happens on a feature/development branch, never directly on `main`.

## Development Guidelines

### Working with Templates

- All templates use the `arrmada.` prefix for helper functions
- Service-specific templates are namespaced in subdirectories
- Use `include` not `template` for helper calls (allows piping)
- Always quote values that might be interpreted as numbers: `port: {{ .Values.sonarr.service.port | quote }}`

### values.yaml Conventions

- Top-level keys: `global`, `sonarr`, `radarr`, `prowlarr`, `recyclarr`, `configSync`
- Each service has: `enabled`, `image`, `service`, `ingress`, `resources`, `persistence`, `config`, `postgresql`
- Config sections mirror the *arr API structure for clarity
- Secrets reference format: use `existingSecret` / `secretKeyRef` patterns

### Testing

```bash
# Lint the chart
helm lint .

# Template rendering (dry run)
helm template arrmada . -f values.yaml

# Template a specific service
helm template arrmada . -f values.yaml -s templates/sonarr/deployment.yaml

# Install with debug
helm install arrmada . -f values.yaml --debug --dry-run
```

### Config Sync Script Pattern

```bash
# Idempotent sync for a resource type
sync_resource() {
  local app=$1 api_version=$2 resource=$3 desired_file=$4

  current=$(curl -s -H "X-Api-Key: $API_KEY" "http://${app}:${PORT}/api/${api_version}/${resource}")
  desired=$(cat "$desired_file")

  # Compare and apply changes
  # POST for new resources, PUT for changed, DELETE for removed (if enabled)
}
```

### Prowlarr Indexer Export Workflow

Since indexer configs are large, sensitive, and user-specific:

1. User runs Prowlarr locally via Docker
2. Configures desired indexers through the UI
3. Runs the export script: `./scripts/prowlarr-export.sh http://localhost:9696 <api-key>`
4. Script outputs a Kubernetes Secret YAML with indexer definitions
5. User applies the secret to their cluster and references it in values.yaml

## Common Commands

```bash
# Render all templates
helm template arrmada .

# Install to cluster
helm install arrmada . -n media --create-namespace

# Upgrade after values change
helm upgrade arrmada . -n media

# Check config sync job logs
kubectl logs -n media job/arrmada-config-sync

# Check recyclarr logs
kubectl logs -n media job/arrmada-recyclarr-sync
```

## External Dependencies

- **PostgreSQL**: Must be provisioned separately. Required databases:
  - `sonarr-main`, `sonarr-log` (owner: configurable)
  - `radarr-main`, `radarr-log` (owner: configurable)
  - `prowlarr-main`, `prowlarr-log` (owner: configurable, optional if using SQLite)
- **Storage**: PVCs for config directories; media volumes typically pre-existing NFS shares
- **Ingress controller**: NGINX ingress controller (or compatible) for external access
- **cert-manager** (optional): For automated TLS certificate management

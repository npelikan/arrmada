# arrmada

Unified Helm chart for the *arr media automation stack — **Sonarr**, **Radarr**, and **Prowlarr** — with **fully declarative configuration**.

Unlike typical charts that only deploy containers, arrmada manages the complete application configuration lifecycle via REST APIs: quality profiles, custom formats, download clients, indexers, media naming, root folders, notifications, and more — all defined as Helm values.

## Features

- **Fully declarative**: All application config is defined in `values.yaml` and synced via API on install/upgrade
- **PostgreSQL-backed**: Sonarr and Radarr use external PostgreSQL; Prowlarr supports it optionally
- **TRaSH Guide integration**: Recyclarr CronJob syncs community-vetted quality profiles and custom formats
- **Prowlarr as indexer hub**: Auto-generates Prowlarr→Sonarr/Radarr application connections
- **Secure by design**: API keys in Kubernetes Secrets; sensitive fields use `${ENV_VAR}` substitution at sync time
- **Multi-ingress**: Each service supports multiple Ingress controllers (nginx, tailscale, etc.)
- **Schema validation**: `values.schema.json` catches invalid API keys, port ranges, and typos at `helm lint` time

## Services

| Service  | Port | API | PostgreSQL |
|----------|------|-----|------------|
| Sonarr   | 8989 | v3  | Required   |
| Radarr   | 7878 | v3  | Required   |
| Prowlarr | 9696 | v1  | Optional   |

## Prerequisites

- Helm 3
- External PostgreSQL with databases pre-created (see [Database Setup](#database-setup))
- PVCs for config storage (or `storageClassName` for dynamic provisioning)
- Existing PVCs for media directories (NFS shares, etc.)

## Quick Start

### Minimal Install (services only, no config sync)

```bash
# Generate API keys
SONARR_KEY=$(openssl rand -hex 16)
RADARR_KEY=$(openssl rand -hex 16)
PROWLARR_KEY=$(openssl rand -hex 16)

# Install
helm install arrmada . -n media --create-namespace \
  --set global.apiKeys.sonarr="${SONARR_KEY}" \
  --set global.apiKeys.radarr="${RADARR_KEY}" \
  --set global.apiKeys.prowlarr="${PROWLARR_KEY}" \
  --set global.postgresql.host="postgres.media.svc.cluster.local" \
  --set global.postgresql.password="changeme"
```

Or use the example values file:

```bash
helm install arrmada . -n media --create-namespace -f examples/values-minimal.yaml
```

### Full Install (with declarative config)

```bash
# Copy and edit the full example
cp examples/values-full.yaml my-values.yaml
# Edit my-values.yaml with your actual settings

helm install arrmada . -n media --create-namespace -f my-values.yaml
```

## Configuration

### Global Settings

```yaml
global:
  env:
    PUID: 1000   # User ID for the *arr processes
    PGID: 1000   # Group ID
    UMASK: "002"

  apiKeys:
    sonarr: ""    # 32-char hex; generate with: openssl rand -hex 16
    radarr: ""
    prowlarr: ""

  # Or reference an existing Secret:
  # existingSecret: my-arrmada-secrets

  postgresql:
    host: "postgres.media.svc.cluster.local"
    port: 5432
    password: "changeme"
    sonarr:
      user: sonarr
      mainDatabase: sonarr-main
      logDatabase: sonarr-log
    radarr:
      user: radarr
      mainDatabase: radarr-main
      logDatabase: radarr-log
    prowlarr:
      enabled: false   # Set true to use PostgreSQL for Prowlarr
      user: prowlarr
      mainDatabase: prowlarr-main
      logDatabase: prowlarr-log
```

### Existing Secret

To avoid storing credentials in `values.yaml`, create a Secret beforehand:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: arrmada-secrets
type: Opaque
stringData:
  sonarr-api-key: "<your-sonarr-api-key>"
  radarr-api-key: "<your-radarr-api-key>"
  prowlarr-api-key: "<your-prowlarr-api-key>"
  postgresql-password: "<your-pg-password>"
```

Then reference it:
```yaml
global:
  existingSecret: arrmada-secrets
```

### Service Configuration

Each service (sonarr, radarr, prowlarr) shares the same base structure:

```yaml
sonarr:
  enabled: true
  image:
    repository: ghcr.io/hotio/sonarr
    tag: release
    pullPolicy: IfNotPresent
  service:
    type: ClusterIP
    port: 8989
  resources: {}
  persistence:
    config:
      enabled: true
      storageClassName: fast-ssd
      size: 5Gi
    media:   # Existing PVCs for media directories
      - name: tv
        claimName: pvc-nfs-tv
        mountPath: /tv
  ingress: []
  config: {}
```

### Ingress

Each service supports a list of Ingress entries (multiple controllers per service):

```yaml
sonarr:
  ingress:
    - name: nginx
      enabled: true
      className: nginx
      annotations:
        cert-manager.io/cluster-issuer: letsencrypt-prod
      hosts:
        - host: sonarr.example.com
          paths:
            - path: /
              pathType: Prefix
      tls:
        - secretName: sonarr-tls
          hosts: [sonarr.example.com]
    - name: tailscale
      enabled: true
      className: tailscale
      hosts:
        - host: sonarr
          paths: [{path: /, pathType: Prefix}]
```

### Declarative Configuration

Enable config sync to manage application settings via values:

```yaml
configSync:
  enabled: true
  deleteUnmanaged: false   # Set true to delete resources not in values
  timeout: 300

sonarr:
  config:
    tags:
      - label: 4k
    rootFolders:
      - path: /tv
    naming:
      renameEpisodes: true
      standardEpisodeFormat: "{Series TitleYear} - S{season:00}E{episode:00} - {Episode CleanTitle} [{Quality Full}]{-Release Group}"
    downloadClients:
      - name: qBittorrent
        implementation: QBittorrent
        configContract: QBittorrentSettings
        fields:
          - {name: host, value: "${QBIT_HOST}"}
          - {name: port, value: 8080}
          - {name: password, value: "${QBIT_PASSWORD}"}
```

#### Sensitive Fields in Download Clients

Use `${ENV_VAR}` syntax for credentials. Mount a Secret with the actual values:

```yaml
configSync:
  extraEnvFrom:
    - secretRef:
        name: arrmada-download-clients

# Secret contents:
# QBIT_HOST: qbittorrent.media.svc.cluster.local
# QBIT_PASSWORD: mypassword
```

#### Managed Resource Types

Config sync manages the following in dependency order:

| Resource | Sonarr | Radarr | Prowlarr | Match Field |
|----------|--------|--------|----------|-------------|
| tags | ✓ | ✓ | ✓ | label |
| rootFolders | ✓ | ✓ | — | path |
| qualityDefinitions | ✓ | ✓ | — | title |
| customFormats | ✓ | ✓ | — | name |
| qualityProfiles | ✓ | ✓ | — | name |
| delayProfiles | ✓ | ✓ | — | id |
| downloadClients | ✓ | ✓ | ✓ | name |
| notifications | ✓ | ✓ | ✓ | name |
| importLists | ✓ | ✓ | — | name |
| config/naming | ✓ | ✓ | — | singleton |
| config/mediaManagement | ✓ | ✓ | — | singleton |
| config/host | ✓ | ✓ | ✓ | singleton |
| config/ui | ✓ | ✓ | ✓ | singleton |
| applications | — | — | ✓ | name |
| indexers | — | — | ✓ | name |

### Prowlarr Application Sync

Prowlarr can automatically push indexer configs to Sonarr and Radarr:

```yaml
prowlarr:
  config:
    applications:
      autoSonarr: true   # Creates Prowlarr→Sonarr connection automatically
      autoRadarr: true   # Creates Prowlarr→Radarr connection automatically
```

Auto-generated connections use the chart-internal service URLs and inject API keys
via `${SONARR_API_KEY}` / `${RADARR_API_KEY}` (resolved at sync time, not stored in ConfigMaps).

### Prowlarr Indexers

Indexers contain sensitive credentials and are managed via a Kubernetes Secret.
See [docs/prowlarr-indexers.md](docs/prowlarr-indexers.md) for the full workflow.

Quick summary:
```bash
# 1. Export indexers from a local Prowlarr
./scripts/prowlarr-export.sh http://localhost:9696 <api-key> > prowlarr-indexers.yaml

# 2. Apply the Secret
kubectl apply -n media -f prowlarr-indexers.yaml
```

Then reference in values:
```yaml
prowlarr:
  config:
    indexers:
      existingSecret: prowlarr-indexers
      secretKey: indexers.json
```

### Recyclarr (TRaSH Guide Sync)

Recyclarr syncs community quality profiles and custom formats from the TRaSH guides:

```yaml
recyclarr:
  enabled: true
  schedule: "0 */6 * * *"   # Every 6 hours
  config:
    sonarr:
      - instance_name: main
        quality_definition:
          type: series
        quality_profiles:
          - name: HD-1080p
        custom_formats:
          - trash_ids:
              - 3a3ff47579026a9e4b651ef28c46b981   # DoVi
            assign_scores_to:
              - name: HD-1080p
                score: 0
    radarr:
      - instance_name: main
        quality_definition:
          type: movie
        quality_profiles:
          - name: HD-1080p
```

API keys are injected via `!env_var SONARR_API_KEY` / `!env_var RADARR_API_KEY`
directly from the chart's Secret — never stored in the ConfigMap.

## Database Setup

PostgreSQL must be provisioned separately. Create the required databases:

```sql
CREATE USER sonarr WITH PASSWORD 'changeme';
CREATE USER radarr WITH PASSWORD 'changeme';
CREATE USER prowlarr WITH PASSWORD 'changeme';

CREATE DATABASE "sonarr-main" OWNER sonarr;
CREATE DATABASE "sonarr-log"  OWNER sonarr;
CREATE DATABASE "radarr-main" OWNER radarr;
CREATE DATABASE "radarr-log"  OWNER radarr;
CREATE DATABASE "prowlarr-main" OWNER prowlarr;   -- Only if prowlarr.postgresql.enabled=true
CREATE DATABASE "prowlarr-log"  OWNER prowlarr;
```

## Operations

```bash
# Install
helm install arrmada . -n media --create-namespace -f values.yaml

# Upgrade after values change
helm upgrade arrmada . -n media -f values.yaml

# Check pod status
kubectl get pods -n media -l app.kubernetes.io/instance=arrmada

# View config sync logs
kubectl logs -n media job/arrmada-config-sync

# View service logs
kubectl logs -n media -l app.kubernetes.io/component=sonarr
kubectl logs -n media -l app.kubernetes.io/component=radarr
kubectl logs -n media -l app.kubernetes.io/component=prowlarr

# Force config re-sync
kubectl delete job -n media arrmada-config-sync
helm upgrade arrmada . -n media -f values.yaml
```

## Development

```bash
# Lint
helm lint .

# Dry-run render
helm template arrmada . -f values.yaml --debug

# Render specific template
helm template arrmada . -f values.yaml -s templates/sonarr/deployment.yaml
```

## License

[Unlicense](LICENSE) — public domain.

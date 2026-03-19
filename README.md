# arrmada

Unified Helm chart for the *arr media automation stack — **Sonarr**, **Radarr**, **Prowlarr**, and **rtorrent** — with **fully declarative configuration**.

Unlike typical charts that only deploy containers, arrmada manages the complete application configuration lifecycle via REST APIs: quality profiles, custom formats, download clients, indexers, media naming, root folders, notifications, and more — all defined as Helm values.

## Features

- **Fully declarative**: All application config is defined in `values.yaml` and synced via API on install/upgrade
- **PostgreSQL-backed**: Sonarr and Radarr use external PostgreSQL; Prowlarr supports it optionally
- **Integrated download client**: rtorrent (rflood) deploys alongside the *arr stack and is auto-registered as a download client in Sonarr and Radarr
- **Shared media volumes**: A single `global.media` array defines NFS/RWX volumes mounted identically by all services — no per-service PVC wiring
- **TRaSH Guide integration**: Recyclarr CronJob syncs community-vetted quality profiles and custom formats
- **Prowlarr as indexer hub**: Auto-generates Prowlarr→Sonarr/Radarr application connections
- **Secure by design**: API keys in Kubernetes Secrets; sensitive fields use `${ENV_VAR}` substitution at sync time
- **Multi-ingress**: Each service supports multiple Ingress controllers (nginx, tailscale, etc.)
- **Schema validation**: `values.schema.json` catches invalid API keys, port ranges, and typos at `helm lint` time

## Services

| Service  | Port(s)        | API | PostgreSQL |
|----------|----------------|-----|------------|
| Sonarr   | 8989           | v3  | Required   |
| Radarr   | 7878           | v3  | Required   |
| Prowlarr | 9696           | v1  | Optional   |
| rtorrent | 3000 (Flood UI), 5000 (RPC) | — | — |

## Prerequisites

- Helm 3
- External PostgreSQL with databases pre-created (see [Database Setup](#database-setup))
- PVCs for config storage (or `storageClassName` for dynamic provisioning)
- ReadWriteMany PVCs for shared media directories (NFS, etc.)

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

### Shared Media Volumes

The `global.media` array defines ReadWriteMany volumes that are mounted at identical paths by Sonarr, Radarr, and rtorrent. This ensures all services see the same filesystem layout.

```yaml
global:
  media:
    - name: data
      mountPath: /data
      existingClaim: pvc-nfs-data   # pre-provisioned ReadWriteMany PVC
      downloadDir: /data/downloads  # rtorrent saves completed downloads here
      tvDir: /data/tv               # auto-added to Sonarr root folders
      moviesDir: /data/movies       # auto-added to Radarr root folders
```

Each entry creates a shared PVC (or uses an existing one) and:
- Mounts it in Sonarr, Radarr, and rtorrent at `mountPath`
- Adds `tvDir` as a Sonarr root folder (via config sync)
- Adds `moviesDir` as a Radarr root folder (via config sync)
- Configures rtorrent's download path to `downloadDir`

**All PVCs must be ReadWriteMany** — Sonarr, Radarr, and rtorrent all mount them simultaneously.

Dynamic provisioning is also supported:
```yaml
global:
  media:
    - name: data
      mountPath: /data
      storageClassName: nfs-csi
      size: 10Ti
      downloadDir: /data/downloads
      tvDir: /data/tv
      moviesDir: /data/movies
```

### Service Configuration

Each *arr service (sonarr, radarr, prowlarr) shares the same base structure:

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

### rtorrent (rTorrent + Flood UI)

rtorrent is deployed using [hotio/rflood](https://hotio.dev/containers/rflood/), which bundles rTorrent with the Flood web interface.

```yaml
rtorrent:
  enabled: true
  service:
    floodPort: 3000   # Flood web UI
    rpcPort: 5000     # XML/JSON-RPC endpoint (used by Sonarr/Radarr)
  persistence:
    config:
      storageClassName: fast-ssd
      size: 1Gi
  ingress:
    - name: nginx
      enabled: true
      className: nginx
      hosts:
        - host: flood.example.com
          paths: [{path: /, pathType: Prefix}]
```

#### RPC Authentication

rflood requires HTTP basic auth on its RPC endpoint. An init container generates a bcrypt htpasswd entry from the configured credentials and writes it to `/config/rpc2/basic_auth_credentials` before the main container starts.

Use an existing Secret (recommended):

```yaml
rtorrent:
  rpcAuth:
    existingSecret: rtorrent-rpc-auth   # must contain 'username' and 'password' keys
```

Or set inline values (password is sensitive — prefer `existingSecret`):

```yaml
rtorrent:
  rpcAuth:
    username: rtorrent
    password: changeme
```

#### Auto-Registration as Download Client

When `rtorrent.enabled: true`, the chart automatically registers rtorrent as a download client in both Sonarr and Radarr using the chart-internal service URL and RPC credentials. You do not need to add it manually under `sonarr.config.downloadClients` or `radarr.config.downloadClients`.

> **Note**: If you define a download client named `rTorrent` manually in `sonarr.config.downloadClients` or `radarr.config.downloadClients`, it will appear as a duplicate alongside the auto-generated entry. Remove the manual entry to avoid duplicates.

Download directories are derived from `global.media[*].downloadDir`.

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

#### Environment Variable Substitution

Use `${ENV_VAR}` syntax anywhere in config values to reference environment variables that are resolved at sync time, not stored in ConfigMaps. This is the recommended way to handle credentials.

Built-in variables injected by the chart:

| Variable | Value |
|----------|-------|
| `${SONARR_API_KEY}` | Sonarr API key from the chart Secret |
| `${RADARR_API_KEY}` | Radarr API key from the chart Secret |
| `${PROWLARR_API_KEY}` | Prowlarr API key from the chart Secret |
| `${RTORRENT_RPC_USERNAME}` | rtorrent RPC username |
| `${RTORRENT_RPC_PASSWORD}` | rtorrent RPC password |

To inject additional secrets (e.g. download client passwords), mount them via `configSync.extraEnvFrom`:

```yaml
configSync:
  extraEnvFrom:
    - secretRef:
        name: arrmada-download-clients

# Secret contents:
# QBIT_HOST: qbittorrent.media.svc.cluster.local
# QBIT_PASSWORD: mypassword
```

Substitution applies to JSON string fields only. The full field value must be the variable reference (e.g. `"${QBIT_HOST}"`) — partial substitution within a string is not supported.

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

#### Drift Reconciliation

By default, config sync only runs on install and upgrade. To also catch manual UI changes, enable periodic reconciliation:

```yaml
configSync:
  schedule: "0 */6 * * *"   # CronJob that re-syncs every 6 hours
```

Leave `schedule` empty (the default) to disable the CronJob.

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
  persistence:
    enabled: true            # Cache TRaSH guide data between runs
    storageClassName: fast-ssd
    size: 2Gi
  config:
    sonarr:
      - instance_name: main
        quality_definition:
          type: series
        quality_profiles:
          - name: HD-1080p
            # include syncs the profile definition (qualities, cutoffs) from TRaSH Guides
            include:
              - trash_id: 76e060895c5b8a765c310933da0a5357  # HD-1080p (Sonarr)
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
            # include syncs the profile definition (qualities, cutoffs) from TRaSH Guides
            include:
              - trash_id: a5db2b67-4a1e-4286-ab16-c39f8a3a8f4b  # HD-1080p (Radarr)
```

API keys are injected via `!env_var SONARR_API_KEY` / `!env_var RADARR_API_KEY`
directly from the chart's Secret — never stored in the ConfigMap.

Enabling `recyclarr.persistence` caches the TRaSH guide data between runs, which is useful when running on a schedule.

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
kubectl logs -n media -l app.kubernetes.io/component=rtorrent

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
helm template arrmada . -f values.yaml -s templates/rtorrent/deployment.yaml
```

## License

[Unlicense](LICENSE) — public domain.

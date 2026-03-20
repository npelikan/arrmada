# Managing Prowlarr Indexers

Arrmada supports two workflows for Prowlarr indexer management. Choose the one
that fits your operational model.

---

## Workflow A: UI-managed (default)

Leave `prowlarr.config.indexers.existingSecret` empty (the default). Arrmada
will not touch indexers at all — add, edit, and remove them directly through the
Prowlarr web UI. This is the simplest option and works well when indexer
configuration doesn't need to be version-controlled or reproduced across clusters.

```yaml
prowlarr:
  config:
    indexers:
      existingSecret: ""   # default — indexers managed through the UI
```

The config sync Job skips the indexer sync step entirely when `existingSecret` is
unset, so `configSync.deleteUnmanaged` has no effect on indexers.

---

## Workflow B: Declarative (GitOps)

Store indexer definitions in a Kubernetes Secret and reference it from
`values.yaml`. On each `helm upgrade` the config sync Job will push the
definitions to Prowlarr via its API (create/update by name, optionally delete
unmanaged). This is the recommended approach for GitOps workflows where you want
full reproducibility.

Indexer configs often contain sensitive credentials (API keys, usernames,
passwords), so they are stored in a Secret rather than inline in `values.yaml`.

```
1. Run Prowlarr locally (Docker)
2. Configure indexers in the UI
3. Export → Kubernetes Secret YAML
4. Apply Secret to cluster
5. Reference in values.yaml
```

### Step 1: Run Prowlarr Locally

Start a temporary Prowlarr container with a local config directory:

```bash
docker run -d \
  --name prowlarr-local \
  -p 9696:9696 \
  -v "${HOME}/.prowlarr-local:/config" \
  ghcr.io/hotio/prowlarr:release
```

Wait for it to start, then open http://localhost:9696 in your browser.

### Step 2: Get the API Key

1. Go to **Settings → General**
2. Copy the **API Key** shown at the top

### Step 3: Configure Indexers

1. Go to **Indexers** → **Add Indexer**
2. Search for and configure each indexer you want
3. Test each indexer to verify connectivity
4. Take note — Prowlarr will store credentials (API keys, cookies, etc.) for each

### Step 4: Export Indexers

Run the export script from the repository root:

```bash
./scripts/prowlarr-export.sh http://localhost:9696 <api-key> prowlarr-indexers media \
  > prowlarr-indexers.yaml
```

This exports all configured indexers as a Kubernetes Secret YAML. The output:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: prowlarr-indexers
  namespace: media
type: Opaque
data:
  indexers.json: <base64-encoded JSON>
```

**Security note**: The exported YAML contains sensitive credentials. Do not
commit it to version control.

### Step 5: Apply the Secret

```bash
kubectl apply -n media -f prowlarr-indexers.yaml
```

### Step 6: Reference in values.yaml

```yaml
prowlarr:
  config:
    indexers:
      existingSecret: prowlarr-indexers
      secretKey: indexers.json   # default, matches the export script output
```

On the next `helm upgrade`, the config sync Job will mount the Secret and
push the indexer definitions to Prowlarr via its API.

### Updating Indexers

To add or update indexers:

1. Start the local Prowlarr container again (or use the in-cluster instance
   if you can port-forward to it)
2. Make changes in the UI
3. Re-run the export script
4. Apply the updated Secret: `kubectl apply -n media -f prowlarr-indexers.yaml`
5. Trigger a config sync: delete the existing Job and let Helm re-run it,
   or run `helm upgrade` to trigger the post-upgrade hook

```bash
kubectl delete job -n media arrmada-config-sync
helm upgrade arrmada . -n media -f values.yaml
```

### Using the In-Cluster Prowlarr

If Prowlarr is already running in your cluster, you can export directly from it:

```bash
# Port-forward to the running Prowlarr
kubectl port-forward -n media svc/arrmada-prowlarr 9696:9696 &

# Get the API key from the chart secret
API_KEY=$(kubectl get secret -n media arrmada-secrets \
  -o jsonpath='{.data.prowlarr-api-key}' | base64 -d)

# Export
./scripts/prowlarr-export.sh http://localhost:9696 "${API_KEY}" > prowlarr-indexers.yaml

# Stop port-forward
kill %1
```

### Secret Format Reference

The `indexers.json` key contains a JSON array where each element is a Prowlarr
indexer object. The structure mirrors the Prowlarr `/api/v1/indexer` API response
with `id` fields removed (Prowlarr assigns new IDs on import).

Key fields per indexer:

| Field | Description |
|-------|-------------|
| `name` | Display name (used for matching on sync) |
| `enable` | Whether the indexer is active |
| `protocol` | `torrent` or `usenet` |
| `implementation` | Prowlarr indexer implementation name |
| `configContract` | Settings contract name |
| `fields` | Array of `{name, value}` settings (may include credentials) |
| `tags` | Array of tag IDs |

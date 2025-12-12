# Nomad Enterprise Server Helm Chart

A Helm chart for deploying HashiCorp Nomad Enterprise Server as a StatefulSet in OpenShift, aligned with HashiCorp Validated Design (HVD) recommendations.

## Prerequisites

- OpenShift 4.x cluster
- Helm 3.x
- Nomad Enterprise license
- MetalLB or equivalent LoadBalancer provider
- A fixed LoadBalancer IP address

## Quick Start

### Install with fixed LoadBalancer IP

```bash
helm install nomad-enterprise ./helm/nomad-enterprise \
  --namespace nomad \
  --create-namespace \
  --set license="<your-nomad-enterprise-license>" \
  --set advertise.address="172.16.101.10" \
  --set service.external.loadBalancerIP="172.16.101.10"
```

### Using values files

```bash
# Development (single replica, minimal resources)
helm install nomad-enterprise ./helm/nomad-enterprise \
  --namespace nomad \
  --create-namespace \
  -f values-dev.yaml \
  --set license="<your-license>" \
  --set advertise.address="172.16.101.10" \
  --set service.external.loadBalancerIP="172.16.101.10"

# Production (3 replicas, audit enabled)
helm install nomad-enterprise ./helm/nomad-enterprise \
  --namespace nomad \
  --create-namespace \
  -f values-production.yaml \
  --set license="<your-license>" \
  --set advertise.address="172.16.101.10" \
  --set service.external.loadBalancerIP="172.16.101.10"
```

## Deployment Profiles

This chart includes two example values files for common deployment scenarios:

### values-dev.yaml
- Single replica
- Minimal resources (100m CPU, 256Mi memory)
- Audit logging disabled
- Persistence disabled (emptyDir)
- Anti-affinity disabled
- Monitoring disabled
- Suitable for: Development, testing, PoC

### values-production.yaml
- 3 replicas
- Production resources (500m-2000m CPU, 1-2Gi memory)
- Audit logging enabled with separate PVC
- ACLs enabled
- Topology spread constraints
- Autopilot configuration
- Monitoring with alerting enabled
- Suitable for: Production workloads

## Configuration

### Core Settings

| Parameter | Description | Default |
|-----------|-------------|---------|
| `replicaCount` | Number of Nomad server replicas | `3` |
| `license` | Nomad Enterprise license (required) | `""` |
| `advertise.address` | External IP for client connections (required) | `""` |
| `gossip.key` | Gossip encryption key (auto-generated if empty) | `""` |

### Topology

| Parameter | Description | Default |
|-----------|-------------|---------|
| `topology.region` | Nomad region name | `"global"` |
| `topology.datacenter` | Nomad datacenter name (defaults to namespace if empty) | `""` |

The `datacenter` defaults to the Kubernetes namespace, providing a natural mapping between Nomad's topology and Kubernetes organization.

### Services

| Parameter | Description | Default |
|-----------|-------------|---------|
| `service.external.type` | External service type | `LoadBalancer` |
| `service.external.loadBalancerIP` | Fixed LoadBalancer IP | `""` |
| `service.internal.type` | Internal service type | `ClusterIP` |
| `service.headless.name` | Headless service name for gossip | `nomad-headless` |

### Persistence

| Parameter | Description | Default |
|-----------|-------------|---------|
| `persistence.enabled` | Enable persistent storage | `true` |
| `persistence.size` | Data volume size | `10Gi` |
| `persistence.audit.enabled` | Enable separate audit PVC | `true` |
| `persistence.audit.size` | Audit volume size | `5Gi` |

### Audit Logging (HVD)

| Parameter | Description | Default |
|-----------|-------------|---------|
| `server.audit.enabled` | Enable audit logging | `true` |
| `server.audit.sink.format` | Audit log format | `json` |
| `server.audit.sink.deliveryGuarantee` | Delivery guarantee | `enforced` |
| `server.audit.sink.rotateDuration` | Log rotation interval | `24h` |
| `server.audit.sink.rotateMaxFiles` | Max rotated files to keep | `15` |

### Snapshots (HVD)

| Parameter | Description | Default |
|-----------|-------------|---------|
| `server.snapshot.enabled` | Enable automated snapshots | `false` |
| `server.snapshot.interval` | Snapshot interval | `1h` |
| `server.snapshot.retain` | Number of snapshots to retain | `24` |
| `server.snapshot.s3.endpoint` | S3/MinIO endpoint | `""` |
| `server.snapshot.s3.bucket` | S3 bucket name | `nomad-snapshots` |
| `server.snapshot.s3.existingSecret` | Secret with S3 credentials | `""` |

### Topology

| Parameter | Description | Default |
|-----------|-------------|---------|
| `affinity.podAntiAffinity.enabled` | Enable pod anti-affinity | `true` |
| `affinity.podAntiAffinity.type` | `preferred` or `required` | `preferred` |
| `topologySpreadConstraints.enabled` | Enable topology spread | `true` |

See [values.yaml](values.yaml) for complete configuration options.

## HVD Alignment Notes

This chart implements HashiCorp Validated Design (HVD) recommendations adapted for Kubernetes environments.

### What's Implemented

#### Audit Logging
Per HVD recommendations, audit logs are enabled by default and written to a separate persistent volume. This ensures:
- Audit data persists independently of application data
- No risk of audit logs filling the data volume
- Compliance with security requirements

#### Automated Snapshots
The chart supports Nomad's built-in snapshot agent for disaster recovery. When enabled, snapshots are automatically taken and uploaded to S3-compatible storage (including MinIO).

#### Gossip Encryption
Gossip encryption is always enabled. A key is auto-generated if not provided.

#### Autopilot
Autopilot is configured for automated cluster management, including dead server cleanup.

### HVD Features NOT Required in Kubernetes

Some HVD recommendations are designed for VM-based deployments and are unnecessary or solved differently in Kubernetes:

#### Redundancy Zones (Not Needed)

The HVD recommends 6 servers with voter/non-voter pairs per availability zone. This pattern provides "hot standby" servers that can be promoted if a voter fails—solving the problem of slow VM recovery times.

**In Kubernetes, this problem is solved differently:**
- Pod rescheduling typically completes within seconds
- StatefulSet preserves pod identity (nomad-0 rejoins as nomad-0 with its existing data)
- Raft consensus handles temporary quorum disruption during reschedule
- Topology spread constraints distribute pods across failure domains

A 3-replica StatefulSet with topology spread constraints provides equivalent availability characteristics without the operational overhead of managing voter/non-voter topology.

#### Manual Availability Zone Distribution (Simplified)

The HVD recommends manually spreading servers across availability zones. In Kubernetes, topology spread constraints achieve this declaratively:

```yaml
topologySpreadConstraints:
  enabled: true
  constraints:
    - maxSkew: 1
      topologyKey: topology.kubernetes.io/zone
      whenUnsatisfiable: DoNotSchedule
```

## Snapshot Configuration

To enable automated snapshots to S3-compatible storage:

### 1. Create S3 Credentials Secret

```bash
oc create secret generic nomad-s3-credentials \
  --namespace nomad \
  --from-literal=access-key-id="YOUR_ACCESS_KEY" \
  --from-literal=secret-access-key="YOUR_SECRET_KEY"
```

### 2. Enable Snapshots in Values

```yaml
server:
  snapshot:
    enabled: true
    interval: "1h"
    retain: 24
    s3:
      endpoint: "https://minio.example.com"
      bucket: "nomad-snapshots"
      region: "us-east-1"
      forcePathStyle: true
      existingSecret: "nomad-s3-credentials"
```

### 3. Install/Upgrade

```bash
helm upgrade nomad-enterprise ./helm/nomad-enterprise \
  --set server.snapshot.enabled=true \
  --set server.snapshot.s3.endpoint="https://minio.example.com" \
  --set server.snapshot.s3.existingSecret="nomad-s3-credentials"
```

## Observability

When `openshift.monitoring.enabled` is true (the default), the chart creates a ServiceMonitor that enables Prometheus to scrape Nomad's metrics endpoint automatically.

### Metrics

Nomad exposes Prometheus-format metrics at `/v1/metrics?format=prometheus`. Key metrics include:

- `nomad_raft_leader` - Whether this server is the Raft leader
- `nomad_raft_peers` - Number of peers in the Raft cluster
- `nomad_client_allocations_*` - Allocation lifecycle metrics
- `nomad_runtime_*` - Go runtime metrics

### Alerting

Optional alerting rules can be enabled:

```bash
helm install nomad-enterprise ./helm/nomad-enterprise \
  --set openshift.monitoring.prometheusRule.enabled=true
```

Default alerts include:
- **NomadServerLeaderLost** (critical) - Cluster has no leader for 1+ minute
- **NomadServerTooFewPeers** (warning) - Fewer peers than expected for 5+ minutes

Additional rules can be added via `openshift.monitoring.prometheusRule.rules`.

### Monitoring Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `openshift.monitoring.enabled` | Enable ServiceMonitor | `true` |
| `openshift.monitoring.serviceMonitor.interval` | Scrape interval | `30s` |
| `openshift.monitoring.serviceMonitor.scrapeTimeout` | Scrape timeout | `10s` |
| `openshift.monitoring.serviceMonitor.additionalLabels` | Labels for Prometheus selector | `{}` |
| `openshift.monitoring.prometheusRule.enabled` | Enable alerting rules | `false` |
| `openshift.monitoring.prometheusRule.rules` | Custom alerting rules | `[]` |

### Grafana Dashboard

A community Grafana dashboard for Nomad is available at https://grafana.com/grafana/dashboards/12787

## Custom Configuration

Nomad merges all `.hcl` files from the config directory alphabetically. Use `server.extraConfig` to add custom configuration:

```yaml
server:
  extraConfig: |
    vault {
      enabled = true
      address = "https://vault.example.com:8200"
    }
```

Or load from a file:

```bash
helm install nomad-enterprise ./helm/nomad-enterprise \
  --set-file server.extraConfig=./custom-config.hcl
```

The custom config is rendered as `90-custom.hcl`, which is merged after `server.hcl`.

## Scaling

To scale the Nomad server cluster:

```bash
helm upgrade nomad-enterprise ./helm/nomad-enterprise --set replicaCount=5
```

The gossip encryption key will be preserved across upgrades.

## Accessing Nomad

- **HTTP API/UI**: Via OpenShift Route (if enabled) or LoadBalancer service
- **RPC (for clients)**: Via LoadBalancer service port 4647

Get the API Route URL:

```bash
oc get route console -n nomad -o jsonpath='{.spec.host}'
```

## ACL Bootstrap

ACL is **disabled by default** for easier initial setup. Once your cluster is running, enable ACL security.

### Manual Bootstrap

#### Step 1: Wait for Cluster Formation

```bash
oc exec -it nomad-enterprise-0 -n nomad -- nomad server members
```

#### Step 2: Bootstrap ACL System

```bash
oc exec -it nomad-enterprise-0 -n nomad -- nomad acl bootstrap
```

**Important**: Save the `Secret ID` from the output immediately.

#### Step 3: Create Anonymous Policy

```bash
cat > anonymous-policy.hcl <<'EOF'
namespace "*" {
  policy       = "read"
  capabilities = ["list-jobs", "read-job"]
}

node {
  policy = "read"
}

agent {
  policy = "read"
}
EOF

export NOMAD_TOKEN="<your-bootstrap-secret-id>"
oc cp anonymous-policy.hcl nomad-enterprise-0:/tmp/anonymous-policy.hcl -n nomad
oc exec -it nomad-enterprise-0 -n nomad -- \
  nomad acl policy apply -token="$NOMAD_TOKEN" \
  anonymous /tmp/anonymous-policy.hcl
```

## Notes

- TLS is disabled by default for PoC - enable via `server.tls.enabled`
- External clients need to reach the LoadBalancer service (ports 4646 and 4647)
- The bootstrap token is a management token with full privileges - store it securely
- ACL bootstrap can only be performed once per cluster unless reset

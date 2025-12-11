# Nomad Enterprise Server Helm Chart

A Helm chart for deploying HashiCorp Nomad Enterprise Server as a StatefulSet in OpenShift.

## Prerequisites

- OpenShift 4.x cluster
- Helm 3.x
- Nomad Enterprise license

## Quick Start

### Install with license string

```bash
helm install nomad-enterprise-server ./helm/nomad-enterprise-server \
  --set license="<your-nomad-enterprise-license>"
```

### Install with license file

```bash
helm install nomad-enterprise-server ./helm/nomad-enterprise-server \
  --set-file license=/path/to/license.hclic
```

## Configuration

Key configuration values:

- `replicaCount`: Number of Nomad server replicas (default: 1)
- `license`: Nomad Enterprise license (required)
- `gossip.key`: Gossip encryption key (auto-generated if empty)
- `service.rpc.type`: Service type for RPC access (ClusterIP/LoadBalancer/NodePort)
- `service.api.type`: Service type for HTTP API access (ClusterIP/LoadBalancer/NodePort)
- `route.enabled`: Enable OpenShift Route for HTTP API (default: true)
- `persistence.enabled`: Enable persistent storage (default: true)
- `persistence.size`: Storage size (default: 10Gi)

See [values.yaml](values.yaml) for complete configuration options.

## Scaling

To scale the Nomad server cluster:

```bash
helm upgrade nomad-enterprise-server ./helm/nomad-enterprise-server --set replicaCount=3
```

The gossip encryption key will be preserved across upgrades.

## Accessing Nomad

- **HTTP API/UI**: Via OpenShift Route (if enabled) or API service
- **RPC (for clients)**: Via RPC service

Get the API Route URL:

```bash
oc get route nomad-enterprise-server-api -n nomad -o jsonpath='{.spec.host}'
```

## ACL Bootstrap (Optional)

ACL is **disabled by default** for easier initial setup and troubleshooting. Once your cluster is running, you can enable ACL security.

### Option 1: Manual Bootstrap (Recommended)

Enable ACL and bootstrap manually after deployment:

### Step 1: Wait for Cluster Formation

Wait for the Nomad cluster to form and elect a leader:

```bash
# Check cluster members
oc exec -it nomad-enterprise-server-0 -n nomad -- nomad server members

# Expected output shows all servers and one leader
# Name                            Address    Port  Status  Leader  Raft Version  Build  Datacenter  Region
# nomad-enterprise-server-0.nomad  10.x.x.x   4648  alive   true    3             1.9.3  dc1         global
```

### Step 2: Bootstrap ACL System

Run the bootstrap command to generate the initial management token:

```bash
oc exec -it nomad-enterprise-server-0 -n nomad -- nomad acl bootstrap
```

**Important**: Save the `Secret ID` from the output immediately. This is your management token and cannot be retrieved again.

Example output:
```
Accessor ID  = a1b2c3d4-...
Secret ID    = e5f6g7h8-...  # SAVE THIS!
Name         = Bootstrap Token
Type         = management
Global       = true
Create Time  = ...
```

### Step 3: Create Anonymous Policy

Create a policy file for unauthenticated requests:

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
```

### Step 4: Apply Anonymous Policy

Set your bootstrap token and apply the anonymous policy:

```bash
# Set token as environment variable
export NOMAD_TOKEN="<your-bootstrap-secret-id>"

# Copy policy file to pod
oc cp anonymous-policy.hcl nomad-enterprise-server-0:/tmp/anonymous-policy.hcl -n nomad

# Create the anonymous policy
oc exec -it nomad-enterprise-server-0 -n nomad -- \
  nomad acl policy apply -token="$NOMAD_TOKEN" \
  anonymous /tmp/anonymous-policy.hcl
```

### Step 5: Verify ACL Setup

```bash
# Test with bootstrap token
oc exec -it nomad-enterprise-server-0 -n nomad -- \
  nomad status -token="$NOMAD_TOKEN"

# Test anonymous access (should work with read-only)
oc exec -it nomad-enterprise-server-0 -n nomad -- nomad status
```

### Step 6: Creating Additional ACL Tokens

After bootstrap, create tokens for specific use cases:

```bash
# Example: Create a token for CI/CD
cat > ci-policy.hcl <<'EOF'
namespace "default" {
  policy       = "write"
  capabilities = ["submit-job", "dispatch-job", "read-logs"]
}
EOF

oc cp ci-policy.hcl nomad-enterprise-server-0:/tmp/ci-policy.hcl -n nomad

oc exec -it nomad-enterprise-server-0 -n nomad -- \
  nomad acl policy apply -token="$NOMAD_TOKEN" ci-policy /tmp/ci-policy.hcl

oc exec -it nomad-enterprise-server-0 -n nomad -- \
  nomad acl token create -token="$NOMAD_TOKEN" -name="CI Token" -policy=ci-policy
```

### Option 2: Automatic Bootstrap (Recommended for Production)

For automated deployments, you can enable ACL with automatic bootstrap using Kubernetes postStart lifecycle hooks:

```bash
helm install nomad-enterprise-server ./helm/nomad-enterprise-server \
  --namespace nomad \
  --set license="<your-license>" \
  --set server.acl.enabled=true \
  --set server.acl.bootstrap.enabled=true
```

**How it works:**
1. Each pod starts its Nomad container with a `postStart` lifecycle hook
2. The postStart hook runs bootstrap logic in parallel with Nomad starting:
   - Waits for local Nomad API to be ready
   - Waits for cluster formation and leader election (default timeout: 300s)
   - Attempts ACL bootstrap (first pod to succeed wins, others get "already bootstrapped")
   - Stores the bootstrap token in `/nomad/data/.bootstrap-token` (persisted in PVC)
   - Applies the anonymous policy for read-only unauthenticated access
   - Exits cleanly
3. Nomad runs as PID 1 with proper signal handling
4. ACL state persists across pod restarts

**Retrieve the bootstrap token:**
```bash
oc exec -it nomad-enterprise-server-0 -n nomad -- cat /nomad/data/.bootstrap-token
```

**Advantages over manual bootstrap:**
- Fully automated during deployment
- Kubernetes-native pattern using postStart lifecycle hooks
- Nomad runs as PID 1 (proper signal handling)
- Hooks run after container starts, so pods can communicate via headless service
- Token persists in PVC (survives pod restarts)
- Race-condition safe (multiple pods can try, first wins)
- Anonymous policy automatically applied

**Configure bootstrap timeout:**
```bash
helm install nomad-enterprise-server ./helm/nomad-enterprise-server \
  --set license="<your-license>" \
  --set server.acl.enabled=true \
  --set server.acl.bootstrap.enabled=true \
  --set server.acl.bootstrap.timeout=600
```

**View bootstrap logs:**
Bootstrap logs are included in the main container logs:
```bash
oc logs nomad-enterprise-server-0 -n nomad | grep -A 20 "ACL Bootstrap"
```

## Notes

- TLS is disabled by default for PoC - enable via `server.tls.enabled`
- External clients need to reach the RPC service (port 4647)
- The bootstrap token is a management token with full privileges - store it securely
- ACL bootstrap can only be performed once per cluster unless reset

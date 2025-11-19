#!/bin/sh
set -e

echo "======================================"
echo "Nomad ACL Bootstrap (postStart hook)"
echo "======================================"

# Check if ACL is already bootstrapped by looking for token file
if [ -f "/nomad/data/.bootstrap-token" ]; then
  echo "ACL already bootstrapped (token file exists)"
  echo "Bootstrap hook complete - nothing to do"
  exit 0
fi

# Wait for local Nomad to start (it's starting in parallel with this hook)
echo "Waiting for Nomad API to be ready..."
ELAPSED=0
until curl -sf http://localhost:4646/v1/agent/health?type=server >/dev/null 2>&1; do
  if [ $ELAPSED -ge 60 ]; then
    echo "ERROR: Timeout waiting for Nomad API to start"
    exit 1
  fi
  sleep 2
  ELAPSED=$((ELAPSED + 2))
done
echo "Nomad API is ready!"

# Wait for leader election across the cluster
echo "Waiting for leader election..."
ELAPSED=0
TIMEOUT=${BOOTSTRAP_TIMEOUT:-300}

until nomad server members 2>/dev/null | grep -q "true"; do
  if [ $ELAPSED -ge $TIMEOUT ]; then
    echo "WARNING: Timeout waiting for leader election after ${TIMEOUT}s"
    echo "Skipping ACL bootstrap..."
    exit 0
  fi
  echo "  Waiting for leader... (${ELAPSED}s/${TIMEOUT}s)"
  sleep 5
  ELAPSED=$((ELAPSED + 5))
done

echo "Leader elected! Cluster is ready."
echo ""
echo "======================================"
echo "Attempting ACL Bootstrap"
echo "======================================"

# Try to bootstrap ACL
BOOTSTRAP_OUTPUT=$(nomad acl bootstrap 2>&1 || true)

if echo "$BOOTSTRAP_OUTPUT" | grep -q "ACL bootstrap already done"; then
  echo "ACL system already bootstrapped (likely by another pod)"
  echo "Init container complete - nothing to do"

elif echo "$BOOTSTRAP_OUTPUT" | grep -q "Secret ID"; then
  echo "Successfully bootstrapped ACL system!"

  # Parse bootstrap token
  BOOTSTRAP_TOKEN=$(echo "$BOOTSTRAP_OUTPUT" | grep "Secret ID" | awk '{print $4}')

  if [ -n "$BOOTSTRAP_TOKEN" ]; then
    echo "Bootstrap token: ${BOOTSTRAP_TOKEN:0:8}..."

    # Store token in persistent volume
    echo "$BOOTSTRAP_TOKEN" > /nomad/data/.bootstrap-token
    chmod 600 /nomad/data/.bootstrap-token
    echo "Token stored in: /nomad/data/.bootstrap-token"

    # Apply anonymous policy if available
    if [ -f "/nomad/acl-policy/anonymous.hcl" ]; then
      echo ""
      echo "Applying anonymous ACL policy..."
      if nomad acl policy apply -token="$BOOTSTRAP_TOKEN" anonymous /nomad/acl-policy/anonymous.hcl; then
        echo "Anonymous policy applied successfully!"
      else
        echo "WARNING: Failed to apply anonymous policy"
      fi
    fi

    echo ""
    echo "======================================"
    echo "ACL Bootstrap Complete!"
    echo "======================================"
    echo "Bootstrap token stored in: /nomad/data/.bootstrap-token"
    echo ""
    echo "To retrieve the token:"
    echo "  oc exec -it <pod-name> -n nomad -- cat /nomad/data/.bootstrap-token"
    echo "======================================"
  else
    echo "ERROR: Failed to parse bootstrap token"
    echo "Bootstrap output:"
    echo "$BOOTSTRAP_OUTPUT"
    exit 1
  fi

else
  echo "ERROR: Unexpected bootstrap response:"
  echo "$BOOTSTRAP_OUTPUT"
  exit 1
fi

echo ""
echo "Init container complete - temporary Nomad will shut down"
exit 0

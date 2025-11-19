#!/bin/sh
set -e

echo "======================================"
echo "Nomad Enterprise Server Entrypoint"
echo "======================================"

# Start Nomad in the background
echo "Starting Nomad server..."
nomad agent -config=/nomad/config/server.hcl &
NOMAD_PID=$!

# Function to forward signals to Nomad process
trap 'kill -TERM $NOMAD_PID' TERM INT

# Wait a moment for Nomad to start
sleep 3

# Check if ACL bootstrap is requested
if [ "$BOOTSTRAP_ACL" = "true" ]; then
  echo ""
  echo "======================================"
  echo "ACL Bootstrap Enabled"
  echo "======================================"

  # Wait for Nomad to be ready and leader elected
  echo "Waiting for leader election..."
  ELAPSED=0
  TIMEOUT=${BOOTSTRAP_TIMEOUT:-300}

  until nomad server members 2>/dev/null | grep -q "true"; do
    if [ $ELAPSED -ge $TIMEOUT ]; then
      echo "WARNING: Timeout waiting for leader election after ${TIMEOUT}s"
      echo "Continuing without ACL bootstrap..."
      break
    fi
    echo "  Waiting for leader... (${ELAPSED}s/${TIMEOUT}s)"
    sleep 5
    ELAPSED=$((ELAPSED + 5))
  done

  # If leader was elected, proceed with bootstrap
  if nomad server members 2>/dev/null | grep -q "true"; then
    echo "Leader elected! Proceeding with ACL bootstrap..."

    # Check if already bootstrapped
    BOOTSTRAP_OUTPUT=$(nomad acl bootstrap 2>&1 || true)

    if echo "$BOOTSTRAP_OUTPUT" | grep -q "ACL bootstrap already done"; then
      echo "ACL system already bootstrapped."
    else
      # Parse bootstrap token
      BOOTSTRAP_TOKEN=$(echo "$BOOTSTRAP_OUTPUT" | grep "Secret ID" | awk '{print $4}')

      if [ -n "$BOOTSTRAP_TOKEN" ]; then
        echo "Bootstrap successful!"
        echo "Secret ID: ${BOOTSTRAP_TOKEN:0:8}..."

        # Store token in file for potential retrieval
        echo "$BOOTSTRAP_TOKEN" > /nomad/data/.bootstrap-token
        chmod 600 /nomad/data/.bootstrap-token

        # Apply anonymous policy if available
        if [ -f "/nomad/acl-policy/anonymous.hcl" ]; then
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
        echo "$BOOTSTRAP_OUTPUT"
      fi
    fi
  fi
fi

echo ""
echo "======================================"
echo "Nomad Server Ready"
echo "======================================"
echo "Following Nomad logs..."
echo ""

# Wait for Nomad process and show its output
wait $NOMAD_PID

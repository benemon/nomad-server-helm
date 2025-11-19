# Nomad Server Configuration
# This file contains server-only configuration

# Data directory
data_dir = "/opt/nomad/data"

# Bind address
bind_addr = "0.0.0.0"

# Server configuration
server {
  enabled = true
  bootstrap_expect = 1

  # Server discovery using static IPs
  server_join {
    retry_join = [
      "node1",
      "node2",
      "node3",
    ]
  }

  # Redundancy zone for HA
  redundancy_zone = "zone-a"

  # Enterprise license
  license_path = "/etc/nomad.d/license.hclic"

  # Gossip encryption - will be set during cluster initialization
  # encrypt = "REPLACE_WITH_GENERATED_KEY"
}

# Client configuration (disabled for server)
client {
  enabled = false
}

# ACL configuration
acl {
  enabled = true
}

# TLS configuration
tls {
  http = true
  rpc = true
  ca_file = "/etc/nomad.d/tls/nomad-agent-ca.pem"
  cert_file = "/etc/nomad.d/tls/nomad-server.pem"
  key_file = "/etc/nomad.d/tls/nomad-server-key.pem"
  verify_server_hostname = false
  verify_https_client = false
}

# Autopilot configuration (Enterprise feature)
autopilot {
  cleanup_dead_servers = true
  last_contact_threshold = "200ms"
  max_trailing_logs = 250
  server_stabilization_time = "10s"
  enable_redundancy_zones = false
  disable_upgrade_migration = false
}

# Telemetry configuration
telemetry {
  collection_interval = "10s"
  disable_hostname = false
  prometheus_metrics = true
  publish_allocation_metrics = true
  publish_node_metrics = true
}

# Logging configuration
log_level = "INFO"
log_json = false
log_file = "/var/log/nomad/nomad.log"
log_rotate_duration = "24h"
log_rotate_max_files = 5

# Plugin directory
plugin_dir = "/home/nomad/plugins"
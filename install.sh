```bash
#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PACKAGES_DIR="$SCRIPT_DIR/packages"

# Docker packages are taken from this repository.
sudo apt-get update

sudo apt-get install -y \
    "$PACKAGES_DIR"/containerd.io_*.deb \
    "$PACKAGES_DIR"/docker-ce-cli_*.deb \
    "$PACKAGES_DIR"/docker-ce_*.deb \
    "$PACKAGES_DIR"/docker-buildx-plugin_*.deb \
    "$PACKAGES_DIR"/docker-compose-plugin_*.deb

# Configure Docker registry mirror.
sudo mkdir -p /etc/docker

sudo tee /etc/docker/daemon.json > /dev/null <<'EOF'
{
  "registry-mirrors": [
    "https://mirror.example.com"
  ]
}
EOF

sudo systemctl enable docker
sudo systemctl restart docker

echo
echo "Installed:"
docker --version
docker compose version

echo
echo "Registry mirror:"
docker info | sed -n '/Registry Mirrors:/,/Live Restore Enabled:/p'
```

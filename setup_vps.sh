#!/usr/bin/env bash
# ==============================================================================
# "Valley Travels and Typing desk" - Private Rendezvous & Relay Server Auto-Deploy
# Architecture: Ubuntu 22.04 / 24.04 LTS (x86_64 / ARM64)
# Ports: 21115 (NAT test), 21116 (TCP/UDP ID/HB), 21117 (Relay), 21118/21119 (Web/API)
# Key Policy: Mandatory ED25519 Encryption Key Pair
# ==============================================================================

set -euo pipefail

echo "===> [1/6] Updating Ubuntu System Repositories..."
sudo apt-get update -y && sudo apt-get upgrade -y
sudo apt-get install -y curl wget ufw git jq net-tools apt-transport-https ca-certificates gnupg lsb-release

echo "===> [2/6] Enabling BBR TCP Congestion Control for Low Latency..."
if ! grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf; then
  echo "net.core.default_qdisc=fq" | sudo tee -a /etc/sysctl.conf
  echo "net.ipv4.tcp_congestion_control=bbr" | sudo tee -a /etc/sysctl.conf
  echo "fs.file-max=1000000" | sudo tee -a /etc/sysctl.conf
  sudo sysctl -p
fi

echo "===> [3/6] Installing Docker Engine & Docker Compose Plugin..."
if ! command -v docker &> /dev/null; then
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt-get update -y
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  sudo systemctl enable --now docker
else
  echo "Docker already installed. Skipping..."
fi

echo "===> [4/6] Configuring UFW Firewall for Zero-Disconnection Ports..."
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp comment 'SSH Port'
sudo ufw allow 21115/tcp comment 'NAT Type Test'
sudo ufw allow 21116/tcp comment 'ID Registration TCP'
sudo ufw allow 21116/udp comment 'Heartbeat & Punching UDP'
sudo ufw allow 21117/tcp comment 'Relay Traffic'
sudo ufw allow 21118/tcp comment 'Web Client WebSocket'
sudo ufw allow 21119/tcp comment 'API / WebSocket'
sudo ufw --force enable

echo "===> [5/6] Creating Persistent Deployment Directory & Docker Compose..."
sudo mkdir -p /opt/valley-desk/data
cd /opt/valley-desk

cat << 'COMPOSE_EOF' > docker-compose.yml
services:
  hbbs:
    image: rustdesk/rustdesk-server:latest
    container_name: valley_hbbs
    restart: always
    command: hbbs -k _
    volumes:
      - ./data:/root
    network_mode: host
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  hbbr:
    image: rustdesk/rustdesk-server:latest
    container_name: valley_hbbr
    restart: always
    command: hbbr -k _
    volumes:
      - ./data:/root
    network_mode: host
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
COMPOSE_EOF

echo "===> [6/6] Launching Private Relay Containers..."
sudo docker compose down --remove-orphans || true
sudo docker compose up -d

sleep 3

echo ""
echo "=========================================================================="
echo " [SUCCESS] Valley Travels and Typing desk Server is LIVE & Running!"
echo "=========================================================================="
echo ""
echo "Public Encryption Key (Mandatory for Client Authorization):"
echo "Copy the key below and save it — you will embed it into your Windows Client build."
echo ""
sleep 2

if [ -f /opt/valley-desk/data/id_ed25519.pub ]; then
  sudo cat /opt/valley-desk/data/id_ed25519.pub
else
  echo "[WAITING] Key file not yet generated. Waiting for container initialization..."
  sleep 5
  sudo cat /opt/valley-desk/data/id_ed25519.pub
fi

echo ""
echo "=========================================================================="
echo "Your VPS Public IP: $(hostname -I | awk '{print $1}')"
echo "=========================================================================="
echo ""
echo "Next Steps:"
echo "1. Copy the PUBLIC KEY above"
echo "2. Save it in your GitHub repo secrets as RUSTDESK_PUBLIC_KEY"
echo "3. Add your VPS IP to GitHub secrets as RUSTDESK_SERVER_IP"
echo "4. Trigger the Windows client build workflow"
echo "=========================================================================="

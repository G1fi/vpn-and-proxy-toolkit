#!/bin/bash
set -e

# ─────────────────────────────────────────────────────────────
# === Environment variables ===
# ─────────────────────────────────────────────────────────────
INSTALL_DIR="/opt/vpn-and-proxy-toolkit"    # The directory where the project will be installed
VPN_DOMAIN="oc.example.com"                 # The domain name where the ocserv server will be hosted
PROXY_DOMAIN="duckduckgo.com"               # The domain name that the Reality proxy will mimic
CAMOUFLAGE_SECRET="secret"                  # The secret phrase used for camouflage
DEFAULT_UPSTREAM="10.0.1.200"               # The default upstream IP address
INTERFACE="eth0"                            # The network interface to use for ocserv

# ─────────────────────────────────────────────────────────────
# === Check for root privileges and configure logging ===
# ─────────────────────────────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
  echo "[!] Please run as root (e.g., via sudo)"
  exit 1
fi

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
exec > >(tee -a "$SCRIPT_DIR/install.log") 2>&1

# ─────────────────────────────────────────────────────────────
# === Copy the project to the target directory ===
# ─────────────────────────────────────────────────────────────
if [[ "$SCRIPT_DIR" != "$INSTALL_DIR" ]]; then
  echo "[*] Copying project to $INSTALL_DIR..."
  rm -rf "$INSTALL_DIR"
  cp -r "$SCRIPT_DIR" "$INSTALL_DIR"

else
  echo "[*] Already in $INSTALL_DIR, skipping copy."
fi

cd "$INSTALL_DIR"

# ─────────────────────────────────────────────────────────────
# === Generate config files from templates ===
# ─────────────────────────────────────────────────────────────
echo "[*] Generating config files..."

for file in \
  "config/nginx/nginx.conf" \
  "config/ocserv/ocserv.conf" \
  "config/ocserv/ssl/cert-template.cfg"
do
  sed -e "s|{{VPN_DOMAIN}}|$VPN_DOMAIN|g" \
      -e "s|{{PROXY_DOMAIN}}|$PROXY_DOMAIN|g" \
      -e "s|{{DEFAULT_UPSTREAM}}|$DEFAULT_UPSTREAM|g" \
      -e "s|{{CAMOUFLAGE_SECRET}}|$CAMOUFLAGE_SECRET|g" \
      "$INSTALL_DIR/${file}.tmpl" > "$INSTALL_DIR/$file"
done

echo "[✓] Config files generated."

# ─────────────────────────────────────────────────────────────
# === System update and package installation ===
# ─────────────────────────────────────────────────────────────
echo "[*] Updating system and installing packages..."

apt-get update
apt-get upgrade -y

echo "[*] Installing build tools and dependencies..."

apt-get install -y \
  build-essential pkg-config \
  libgnutls28-dev libev-dev libreadline-dev \
  libpam0g-dev liblz4-dev libseccomp-dev \
  libnl-route-3-dev libkrb5-dev libradcli-dev \
  libcurl4-gnutls-dev libcjose-dev libjansson-dev liboath-dev \
  libprotobuf-c-dev libtalloc-dev libhttp-parser-dev protobuf-c-compiler \
  gperf iperf3 lcov libuid-wrapper libpam-wrapper libnss-wrapper \
  libsocket-wrapper gss-ntlmssp haproxy iputils-ping freeradius \
  gawk gnutls-bin iproute2 yajl-tools tcpdump \
  ronn ipcalc-ng curl ufw

echo "[✓] Build tools and dependencies installed."

# ─────────────────────────────────────────────────────────────
# === Install Docker ===
# ─────────────────────────────────────────────────────────────
echo "[*] Installing Docker..."
curl -fsSL https://get.docker.com | sh

echo "[*] Enabling Docker service..."
systemctl enable docker
systemctl start docker

echo "[✓] Docker installed and started."

# ─────────────────────────────────────────────────────────────
# === UFW firewall configuration ===
# ─────────────────────────────────────────────────────────────
echo "[*] Configuring UFW firewall..."

ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp  # SSH
ufw allow 80/tcp  # HTTP
ufw allow 443/tcp # HTTPS
ufw --force enable

echo "[✓] UFW firewall enabled with ports 22, 80, 443 allowed."

# ─────────────────────────────────────────────────────────────
# === Download, build and install ocserv ===
# ─────────────────────────────────────────────────────────────
echo "[*] Downloading and building ocserv..."
cd /tmp
wget ftp://ftp.infradead.org/pub/ocserv/ocserv-1.3.0.tar.xz
tar xvf ocserv-1.3.0.tar.xz
cd ocserv-1.3.0
./configure
make -j"$(nproc)"
make install
echo "[✓] ocserv built and installed."

# ─────────────────────────────────────────────────────────────
# === Configure ocserv ===
# ─────────────────────────────────────────────────────────────
echo "[*] Linking ocserv config..."

rm -rf /etc/ocserv
ln -sf "$INSTALL_DIR/config/ocserv" /etc/ocserv

echo "[✓] Done linking ocserv config."

# ─────────────────────────────────────────────────────────────
# === Generate self-signed certificate ===
# ─────────────────────────────────────────────────────────────
echo "[*] Generating self-signed certificate..."

certtool --generate-privkey > "$INSTALL_DIR/config/ocserv/ssl/privkey.pem"
certtool --generate-self-signed \
  --load-privkey "$INSTALL_DIR/config/ocserv/ssl/privkey.pem" \
  --outfile "$INSTALL_DIR/config/ocserv/ssl/fullchain.pem" \
  --template "$INSTALL_DIR/config/ocserv/ssl/cert-template.cfg"

echo "[✓] Done generating self-signed certificate."

# ─────────────────────────────────────────────────────────────
# === Install ocserv systemd service ===
# ─────────────────────────────────────────────────────────────
echo "[*] Creating ocserv systemd service..."

ln -sf "$INSTALL_DIR/config/ocserv/ocserv.service" /etc/systemd/system/ocserv.service
systemctl daemon-reload
systemctl enable ocserv
systemctl start ocserv

echo "[✓] Systemd service installed and started."

# ─────────────────────────────────────────────────────────────
# === Enable IP forwarding and configure NAT ===
# ─────────────────────────────────────────────────────────────
echo "[*] Enabling IP forwarding..."

echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p

echo "[*] Configuring NAT..."
iptables -t nat -A POSTROUTING -o "$INTERFACE" -j MASQUERADE

echo "[✓] IP forwarding and NAT configured."

# ─────────────────────────────────────────────────────────────
# === Start Docker containers ===
# ─────────────────────────────────────────────────────────────
echo "[*] Starting Docker containers via docker compose..."
docker compose -f "$INSTALL_DIR/docker-compose.yml" up -d

# ─────────────────────────────────────────────────────────────
# === Final instructions ===
# ─────────────────────────────────────────────────────────────
echo "[✓] Setup complete: nginx, ocserv, and 3x-ui are up and running from $INSTALL_DIR."

cat <<EOF

[i] To access the 3x-ui web admin interface via SSH tunnel:
    Run this on your local machine:

    ssh -L 2053:localhost:2053 <your_server_user>@<your_server_ip>

Then open your browser and go to: http://localhost:2053

EOF

# VPN and Proxy Toolkit

This project automates the installation and configuration of a full-featured VPN and proxy toolkit, including:

- **ocserv** — An OpenConnect server compatible with Cisco AnyConnect clients.
- **3x-ui** — A Docker-based interface for creating stealthy VLESS/VMess proxies.
- **nginx** — A reverse proxy using SNI-based routing, also in Docker.

Once installed, this setup allows you to share a single `443` port among VPN, proxy, or any other HTTPS-based upstream depending on the domain.
This project was originally developed to securely access my homelab services externally and also serves as a laboratory for discipline-specific work at the university.

---

## Requirements

- Personal domain or DDNS (e.g., `freemyip.com`)
- Ubuntu server with `sudo` (root) access
- Available ports: `80`, `443`, `1443`
- Stable internet connection

## Tested On

- Ubuntu 22.04.2 LTS

---

## Project Structure

```bash
vpn-and-proxy-toolkit/
├── config/
│   ├── nginx/
│   │   └── nginx.conf.tmpl
│   ├── ocserv/
│   │   ├── ocserv.conf.tmpl
│   │   ├── ssl/
│   │   │   └── cert-template.cfg.tmpl
│   └── ...
├── docker-compose.yml
├── install.sh
├── LICENSE
└── README.md
```

---

## TODO

- [ ] Add `acme.sh` support for automatic SSL certificate generation

---

## Installation

### 1. Clone the repository and edit `install.sh`

```bash
git clone https://github.com/G1fi/vpn-and-proxy-toolkit.git
cd vpn-and-proxy-toolkit
nano install.sh
```

### 2. Customize variables in `install.sh`

```bash
INSTALL_DIR="/opt/vpn-and-proxy-toolkit"    # Installation path
VPN_DOMAIN="oc.example.com"                 # Domain for the ocserv VPN
PROXY_DOMAIN="duckduckgo.com"               # Domain to mimic in Reality proxy
CAMOUFLAGE_SECRET="secret"                  # Secret key for camouflage
DEFAULT_UPSTREAM="10.0.1.200"               # Default upstream IP
INTERFACE="eth0"                            # Network interface for ocserv
```

### 3. Run the installer

```bash
chmod +x install.sh
sudo ./install.sh
```

### 4. Follow on-screen instructions to complete setup

---

## Usage

### Creating an ocserv user

```bash
ocpasswd -c /etc/ocserv/ocpasswd <username>
```

### Configuring user-specific settings

By default, users without individual config files are routed only within the VPN subnet.
To customize behavior, create a per-user config:

```bash
nano /etc/ocserv/config-per-user/<username>
```

Example configurations (`default`, `example`) are available by default:

```conf
# Assign static IP
explicit-ipv4 = 10.0.71.50

# Route all traffic through tunnel
route = default
```

Or:

```conf
# Assign static IP
explicit-ipv4 = 10.0.71.100

# Only route specific subnet through tunnel
route = 10.0.1.0/24
# Optional: let server know client handles this subnet
# iroute = 10.0.1.0/24
```

### Connecting to ocserv

#### Linux

```bash
sudo openconnect "https://oc.example.com/?<CAMOUFLAGE_SECRET>"
```

#### Windows & Android

Use Cisco AnyConnect VPN clients.

---

### Accessing the 3x-ui Web Interface

To access the 3x-ui dashboard:

```bash
ssh -L 2053:localhost:2053 <your_user>@<your_server_ip>
```

Then open your browser: [http://localhost:2053](http://localhost:2053)

---

### Creating a Reality Proxy and Users in 3x-ui

- Use **TCP** protocol and port **443**
- Enable **Proxy Protocol** support
- Set destination and SNI to:
  - `<PROXY_DOMAIN>:443` (Destination)
  - `<PROXY_DOMAIN>` (SNI)
- Use Flow: `xtls-rprx-vision`

---

### Connecting to Reality Proxy

#### Linux & Windows

Use **Hiddify** or **NekoBox**

#### Android

Use **husi** or **NekoBox**

#### iOS

Use **FoXray**

---

## License

MIT License — Free to use, modify, and distribute.

---

## Credits

- [ocserv](https://gitlab.com/openconnect/ocserv/)
- [3x-ui](https://github.com/MHSanaei/3x-ui)
- [Docker](https://www.docker.com/)

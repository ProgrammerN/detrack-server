# Deploy Detrack on AWS (low cost)

Recommended setup: **AWS Lightsail** at about **$7/month** (1 GB RAM, 1 vCPU, 40 GB SSD, static IP included).

## Cost breakdown

| Service | Monthly cost | Notes |
|---------|--------------|-------|
| Lightsail `micro_3_0` | **$7** | Enough for a small fleet with embedded H2 database |
| Lightsail `nano_3_0` | $5 | 512 MB RAM — too tight for Java + build; not recommended |
| RDS / separate DB | $15+ | Skip — use embedded H2 on the same instance |
| Application Load Balancer | $16+ | Skip — use Nginx on the same instance |
| Route 53 hosted zone | $0.50 | Optional if you use your own domain |

**Typical total: $7–8/month** (Lightsail only, no domain).

## What gets installed

- Detrack server built from your GitHub fork
- Detrack web UI (submodule)
- Embedded **H2 database** (no RDS cost)
- **Nginx** reverse proxy on port 80/443
- Optional **Let's Encrypt** HTTPS if you set `DOMAIN` and `ADMIN_EMAIL`
- Firewall rules for web + common GPS ports (5001–5100)

## Prerequisites

1. [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) configured (`aws sts get-caller-identity`)
2. [GitHub CLI](https://cli.github.com/) logged in (`gh auth login`) — needed for private repo clone on the server
3. Push the `setup/aws/` files to GitHub before deploying (install script clones from your repo)

## Quick deploy

```bash
chmod +x setup/aws/deploy-lightsail.sh

# HTTP only (use the instance public IP)
./setup/aws/deploy-lightsail.sh

# With HTTPS on your domain
DOMAIN=track.yourdomain.com ADMIN_EMAIL=you@example.com ./setup/aws/deploy-lightsail.sh
```

First boot takes **15–25 minutes** (clone, Gradle build, npm build). Monitor:

```bash
ssh ubuntu@<PUBLIC_IP> 'sudo tail -f /var/log/detrack-install.log'
```

When finished:

- Web UI: `http://<PUBLIC_IP>` or `https://track.yourdomain.com`
- Default login: **admin / admin** — change this immediately in Settings → Users

## Open more GPS ports

Devices use protocol-specific ports. Open additional ranges in Lightsail:

```bash
aws lightsail open-instance-public-ports \
  --instance-name detrack-server \
  --port-info fromPort=5101,toPort=5200,protocol=tcp
```

See [Traccar protocols](https://www.traccar.org/protocols/) for port numbers.

## Manual install (existing Ubuntu server)

```bash
export GITHUB_TOKEN=$(gh auth token)
export DOMAIN=track.yourdomain.com      # optional
export ADMIN_EMAIL=you@example.com      # optional
sudo -E bash setup/aws/install.sh
```

## Upgrading

```bash
ssh ubuntu@<PUBLIC_IP>
sudo systemctl stop detrack
cd /opt/detrack-src && sudo git pull && sudo git submodule update --init --recursive
sudo bash /opt/detrack-src/setup/aws/install.sh
```

## Scaling up later

If you outgrow 1 GB RAM or H2:

- Upgrade Lightsail bundle: `small_3_0` (2 GB, $12/mo)
- Move to MySQL on the same instance (add ~$0, uses local disk)
- Or add Lightsail managed MySQL (+$15/mo) for production workloads

## Security checklist

- [ ] Change default admin password
- [ ] Enable HTTPS with a real domain
- [ ] Restrict SSH to your IP in Lightsail networking
- [ ] Set up Lightsail snapshots ($1/mo for 20 GB) for backups

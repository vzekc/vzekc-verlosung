# Auto-Deploy Discourse on CI Success

When CI passes on `main` for `vzekc/vzekc-verlosung` or `vzekc/vzekc-map`, a GitHub webhook notifies the production server, which automatically rebuilds Discourse.

## How It Works

```
GitHub Actions CI passes on main
  → GitHub sends workflow_run webhook (HTTPS, HMAC-signed)
  → adnanh/webhook on server port 9000
  → validates HMAC-SHA256 signature + event/action/conclusion/branch
  → runs rebuild-discourse.sh (flock prevents concurrent rebuilds)
  → ./launcher rebuild web
```

## Server Setup

### 1. Install webhook

The Debian `webhook` package is used. It provides a systemd unit that listens on port 9000 and expects its config at `/etc/webhook.conf`.

```bash
apt-get install -y webhook
```

### 2. Generate a webhook secret

```bash
openssl rand -hex 32
```

Save this secret — you'll need it for both the server config and GitHub.

### 3. Deploy files

```bash
# Install the hook configuration (the Debian service expects this path)
cp hooks.json /etc/webhook.conf

# Replace the placeholder with your actual secret
sed -i "s/{{ WEBHOOK_SECRET }}/YOUR_SECRET_HERE/" /etc/webhook.conf

# Install the rebuild script
cp rebuild-discourse.sh /usr/local/bin/rebuild-discourse.sh
chmod +x /usr/local/bin/rebuild-discourse.sh
```

### 4. Start the service

```bash
systemctl enable webhook
systemctl start webhook
systemctl status webhook
```

### 5. Configure GitHub Webhooks

For **each** repo (`vzekc/vzekc-verlosung` and `vzekc/vzekc-map`):

1. Go to **Settings → Webhooks → Add webhook**
2. **Payload URL**: `http://YOUR_SERVER:9000/hooks/discourse-rebuild`
3. **Content type**: `application/json`
4. **Secret**: the secret generated in step 2
5. **Events**: select **"Let me select individual events"**, then check only **"Workflow runs"**
6. Click **Add webhook**

## vzekc-map CI

The `vzekc-map` repo needs a CI workflow before webhooks will work. Add `.github/workflows/ci.yml`:

```yaml
name: Discourse Plugin
on:
  push:
    branches: [main]
  pull_request:
jobs:
  ci:
    uses: discourse/.github/.github/workflows/discourse-plugin.yml@v1
```

Then configure the GitHub webhook as described above.

## Security

The webhook listener runs on port 9000 without TLS. This is acceptable because:

- **HMAC-SHA256 verification** rejects forged requests
- The webhook payload contains only public info (repo name, branch, CI status)
- The only action triggered is a Discourse rebuild (idempotent, non-destructive)
- Worst-case replay attack just triggers an unnecessary rebuild

### Optional Hardening

**Restrict port 9000 to GitHub IPs:**

```bash
# Fetch GitHub webhook IP ranges
curl -s https://api.github.com/meta | jq -r '.hooks[]'

# Add UFW rules (example)
ufw default deny incoming
ufw allow from 140.82.112.0/20 to any port 9000
ufw allow from 185.199.108.0/22 to any port 9000
# ... add all ranges from the API response
```

**Add TLS with Caddy** (if you set up a subdomain):

```
webhook.example.com {
    reverse_proxy localhost:9000
}
```

## Verification

```bash
# 1. Check service is running
systemctl status webhook
journalctl -u webhook -f

# 2. Test signature rejection (should fail — no valid signature)
curl -X POST http://localhost:9000/hooks/discourse-rebuild

# 3. Push a trivial commit to main, wait for CI to pass, then monitor:
journalctl -u webhook -f
tail -f /var/log/discourse-rebuild.log

# 4. Check GitHub webhook delivery log:
#    Repo → Settings → Webhooks → Recent Deliveries
```

## Troubleshooting

| Problem | Check |
|---------|-------|
| Service won't start (`ConditionPathExists` failed) | `/etc/webhook.conf` must exist — did you copy `hooks.json` there? |
| Webhook not receiving requests | `journalctl -u webhook -f`, GitHub delivery log shows green 200? |
| Hook returns 200 but no rebuild | Check trigger rules — event, action, conclusion, branch all match? |
| Rebuild fails | `tail -f /var/log/discourse-rebuild.log`, try `./launcher rebuild web` manually |
| Concurrent rebuilds skipped | Expected — `flock` ensures only one rebuild at a time |
| Permission denied on rebuild | The Debian webhook service runs as root by default (needed for Docker/launcher) |
| Secret mismatch | Verify `/etc/webhook.conf` has the correct secret (no `{{ }}` placeholders left) |

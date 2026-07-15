# Getting Started

This guide walks through setting up Soul/ from a fresh clone.

Soul/ is early experimental local assistant software. The project is Linux-first right now because active cleanup/restore workflows assume Linux-style filesystem and Trash behavior.

## 1. Clone the repository

```bash
git clone https://github.com/Unhall0w3d/soul-slash.git
cd soul-slash
```

## 2. Check local tools

```bash
make check
```

Required tools:

- Ruby
- Git
- Make
- curl
- unzip

Recommended tools:

- jq
- zip
- Python 3

## 3. Choose a runtime provider

Soul/ uses a local model runtime through an OpenAI-compatible API.

Supported providers:

- llama.cpp server
- Ollama

Use llama.cpp if you want direct GGUF control and explicit runtime flags.

Use Ollama if you want simpler local model management with `ollama pull`.

## 4. Detect what is already available

```bash
make detect
```

This checks:

- runtime binaries
- common `/v1` endpoints
- Ollama native `/api/tags`
- current `.env`
- local GGUF model files in `./models` and `~/Downloads`

## 5. Run guided setup

```bash
make setup
```

If both llama.cpp and Ollama are detected, setup will ask which provider to configure.

If `.env` already points to a reachable runtime, setup will ask before reconfiguring it. Amazing, a setup script that does not immediately stomp on working config. Nature is healing.

## 6. llama.cpp setup

```bash
make setup-llamacpp
```

The setup script will:

1. detect or ask for `llama-server`
2. ask for host, port, and OpenAI-compatible base URL
3. ask for the model alias
4. search for GGUF files in `./models` and `~/Downloads`
5. offer to use a detected GGUF file
6. otherwise ask for a Hugging Face GGUF URL
7. download the model if needed
8. validate the model file starts with `GGUF`
9. write `.env`

Default tested llama.cpp model:

```text
Qwen3-8B-Q4_K_M.gguf
```

Default tested alias:

```text
soul-qwen3-8b-q4
```

Start llama.cpp in the foreground:

```bash
make start-llamacpp
```

Then open another terminal and test:

```bash
make test-runtime
```

## 7. Ollama setup

```bash
make setup-ollama
```

The setup script will:

1. detect `ollama`
2. ask for the OpenAI-compatible base URL
3. ask for the Ollama model name
4. check whether the model is already installed
5. run `ollama pull` only if needed
6. check the `/v1/models` endpoint
7. write `.env`

Example model:

```text
qwen3:8b
```

Test:

```bash
make test-runtime
```

## 8. Show local configuration

```bash
make env-show
```

Local settings are stored in:

```text
.env
```

`.env` should not be committed.

## 9. Runtime tests

Run all runtime tests:

```bash
make test-runtime
```

Run only FAST mode:

```bash
make test-fast
```

Run only THINK mode:

```bash
make test-think
```

FAST mode uses `/no_think` for models that support it.

THINK mode allows the model to use a larger token budget.

## 10. Soul/ CLI tests

```bash
make test-soul
```

This runs:

```bash
ruby bin/soul doctor
ruby bin/soul skills
ruby bin/soul skill system.status
```

## 11. Start the foreground dashboard

```bash
make dashboard
```

Open `http://127.0.0.1:4567/` locally. The dashboard includes Chat, Skill Studio, and Self Improvement. It binds to loopback only, runs in the foreground, and stops with Ctrl+C.

First-run dashboard access uses the fixed administrator username `admin` and bootstrap password `soul123`. The bootstrap session cannot load dashboard data. Replace it with a private password of 12–128 characters when prompted. Soul stores only the salted derived credential under ignored `Soul/runtime/dashboard_auth/` storage.

If the administrator password is lost, stop the dashboard and explicitly restore the bootstrap gate:

```bash
make dashboard-reset-admin
```

This revokes active sessions and again requires password replacement. It does not start the dashboard.

Use an ignored local `.env` or an invocation-only override for a different port:

```bash
ruby bin/soul dashboard --set dashboard.port=4568
```

Do not commit operator-specific hostnames, addresses, credentials, model aliases, or filesystem paths.

The authenticated dashboard is still loopback-only. Do not widen the bind host for LAN access until the separately reviewed protected-transport phase is complete.

## 12. Optional persistent LAN dashboard

The reviewed Linux deployment keeps Soul on loopback and uses Caddy for HTTPS on one exact LAN address. Complete the first-login password change above before installing it.

1. Install Caddy using your distribution's trusted package source. On Arch/CachyOS: `sudo pacman -S caddy`.
2. Give this user a boot-started systemd user manager, if it does not already have one: `sudo loginctl enable-linger "$USER"`.
3. Give the host a stable LAN IPv4 address, preferably with a DHCP reservation.
4. Preview without writing anything:

   ```bash
   make dashboard-service-plan LAN_HOST=<assigned-lan-ip>
   ```

5. After reviewing the plan, install exactly the two approved user services:

   ```bash
   make dashboard-service-install \
     LAN_HOST=<assigned-lan-ip> \
     CONFIRM=INSTALL_SOUL_LAN_SERVICES
   ```

6. If UFW denies incoming traffic, add a rule limited to the trusted LAN and exact host rather than allowing the port globally:

   ```bash
   sudo ufw allow from <trusted-lan-cidr> to <assigned-lan-ip> port 8443 proto tcp comment 'Soul dashboard LAN HTTPS'
   ```

7. Copy only `~/.local/share/caddy/pki/authorities/local/root.crt` to each selected device, install it as a trusted CA, and verify the browser shows no certificate warning at `https://<assigned-lan-ip>:8443/`. Never copy Caddy's private CA key.
8. Verify login, refresh, and logout from the client device. Check local service state with `make dashboard-service-status` and logs with `make dashboard-service-logs`.

Soul does not change the firewall, router, DHCP, client trust store, or Internet exposure automatically. Full security boundaries and rollback instructions are in `docs/soul/LOCAL_SYSTEMD_HTTPS_DEPLOYMENT.md`.

## 12. Try intent routing

```bash
ruby bin/soul intent "run a file cleanup in Downloads"
ruby bin/soul intent "restore the last downloads cleanup"
```

## 13. Try the cleanup workflow

Create harmless test fixtures. Avoid protected terms like `soul` or `Aletheia` in the filenames.

```bash
mkdir -p ~/Downloads/restore-fixture-folder
touch ~/Downloads/restore-fixture-file.tmp
touch -d "10 days ago" ~/Downloads/restore-fixture-file.tmp
touch -d "10 days ago" ~/Downloads/restore-fixture-folder
```

Run cleanup:

```bash
ruby bin/soul do "cleanup files in my downloads folder older than 3 days"
ruby bin/soul respond "move all"
ruby bin/soul respond "yeah, do it"
```

Run restore:

```bash
ruby bin/soul do "restore the last downloads cleanup"
ruby bin/soul respond "restore all"
ruby bin/soul respond "yeah, do it"
```

Verify:

```bash
ls -la ~/Downloads | grep restore-fixture
```

Clean up:

```bash
rm -rf ~/Downloads/restore-fixture-file.tmp ~/Downloads/restore-fixture-folder
```

## 14. Reflection

After a successful workflow:

```bash
ruby bin/soul reflect last
ruby bin/soul reflection show latest
```

Approve only useful candidates:

```bash
ruby bin/soul reflection approve latest --note "Approved after review"
```

Reject weak or generic candidates:

```bash
ruby bin/soul reflection reject latest --reason "Not useful"
```

## 15. Common Make targets

```text
make help             Show available targets
make check            Check required/recommended local tools only
make detect           Detect runtimes, endpoints, config, and local GGUF models
make setup            Guided runtime setup
make setup-llamacpp   Configure llama.cpp provider
make setup-ollama     Configure Ollama provider
make test-runtime     Test configured runtime
make test-fast        Test FAST/no_think request mode
make test-think       Test THINK request mode
make test-soul        Run basic Soul/ CLI checks
make doctor           Run Soul/ doctor
make env-show         Show local runtime config
make fix-mtimes       Touch repo files if ZIP timestamps caused Make clock-skew warnings
```

## 16. Clock-skew warning after applying overlays

If `make` complains that files have modification times in the future, run:

```bash
make fix-mtimes
```

This touches working-tree files to your current local system time.

It is not elegant. It is a broom. Sometimes a broom is exactly the tool.

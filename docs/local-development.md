# Local Development

The `dev/` directory contains a consumer app for local testing. It is **not published** with the package.

---

## How It Works

The `wippy.lock` file points to the local `src/` directory, so changes to the package source are picked up immediately:

```yaml
directories:
  modules: .wippy
  src: ./dev
replacements:
  - from: butschster/telegram
    to: ./src
```

---

## Getting Started

1. Get a bot token from [@BotFather](https://t.me/BotFather)
2. Copy your token into `dev/.env`
3. Expose your local server (e.g. via ngrok: `ngrok http 8080`)
4. Set `TELEGRAM_WEBHOOK_URL` to your ngrok URL + `/telegram/webhook`
5. Start the server:
   ```bash
   wippy run
   ```
6. Register the webhook:
   ```bash
   wippy run -x telegram.handler:register_webhook
   ```
7. Send `/start` to your bot

---

## Useful Commands

```bash
# Start the dev server
wippy run

# Register webhook with Telegram
wippy run register-webhook

# Remove webhook
wippy run delete-webhook

# Lint a specific namespace
wippy lint --ns=telegram
wippy lint --ns=telegram.*
wippy lint --ns=telegram.sdk
```

---

## Dev Directory Structure

```
dev/
├── _index.yaml   # app: HTTP server, router, env storage, ns.dependency
└── .env          # Bot token and webhook config
```

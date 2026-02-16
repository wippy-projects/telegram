# Installation & Configuration

How to add the Telegram package to your Wippy application and configure it.

---

## 1. Create `src/_telegram.yaml`

The dependency and its router **must** live in a separate file with `namespace: telegram` (matching the package's own
namespace). This is required because the webhook endpoint resolves its router reference at entry load time — before
`ns.requirement` parameter injection takes place. By defining the router in the package's namespace, the reference
`telegram:router` exists when the endpoint needs it.

```yaml
# src/_telegram.yaml
version: "1.0"
namespace: telegram

entries:
  - name: dep.telegram
    kind: ns.dependency
    component: butschster/telegram
    version: "*"
    parameters:
      - name: telegram:webhook_router
        value: telegram:router
      - name: telegram:env_storage
        value: app:env_file

  # Router must be defined here (in the telegram namespace) so that
  # telegram.handler:webhook.endpoint can resolve its meta.router reference.
  - name: router
    kind: http.router
    meta:
      server: app:gateway
    prefix: /telegram
```

> **Known limitation:** Ideally you should be able to pass any router (e.g. `app:my_router`) as the `webhook_router`
> parameter and define everything in your app's namespace. Currently `ns.requirement` injection happens after entry
> references are resolved, so this workaround is needed. This will be fixed in a future Wippy release.

---

## 2. App Infrastructure

Your app's `_index.yaml` should already have these (or similar) entries:

```yaml
# src/_index.yaml
version: "1.0"
namespace: app

entries:
  # ── Infrastructure ─────────────────────────────────

  - name: env_file
    kind: env.storage.file
    file_path: ./.env
    auto_create: true
    file_mode: 0600

  - name: processes
    kind: process.host
    lifecycle:
      auto_start: true

  - name: gateway
    kind: http.service
    addr: ":8080"
    lifecycle:
      auto_start: true
```

---

## 3. Environment Variables

Set these in your `.env` file:

| Variable                  | Required    | Description                                                              |
|---------------------------|-------------|--------------------------------------------------------------------------|
| `TELEGRAM_BOT_TOKEN`      | Yes         | Bot token from [@BotFather](https://t.me/BotFather)                      |
| `TELEGRAM_WEBHOOK_URL`    | Yes         | Public URL for webhook (e.g. `https://your-domain.com/telegram/webhook`) |
| `TELEGRAM_WEBHOOK_SECRET` | Recommended | Secret token for webhook validation                                      |

```env
TELEGRAM_BOT_TOKEN=123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11
TELEGRAM_WEBHOOK_URL=https://your-domain.com/telegram/webhook
TELEGRAM_WEBHOOK_SECRET=your-random-secret-string
```

---

## 4. Register the Webhook

After configuration, register the webhook with Telegram:

```bash
wippy run register-webhook
```

This verifies your bot token via `getMe`, then registers the webhook URL with Telegram.

To remove the webhook later:

```bash
wippy run delete-webhook
```

---

## 5. Start the Server

```bash
wippy run
```

The webhook endpoint listens at `POST /telegram/webhook` (path relative to your router prefix).

---

## Requirements Summary

The package declares three `ns.requirement` entries that consumers must provide:

| Requirement      | Injects Into                         | Description                                   |
|------------------|--------------------------------------|-----------------------------------------------|
| `webhook_router` | `.meta.router` on webhook endpoint   | HTTP router where the endpoint mounts         |
| `env_storage`    | `.storage` on `env.variable` entries | Backend for bot token and secrets             |
| `process_host`   | `.host` on `process.service` entries | Execution host (for future stateful handlers) |

# 🛡️ Shopify Store Dev — Safe AI-Powered Theme Development

> Your AI agent can directly edit your Shopify store. This skill makes sure it doesn't break anything.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## The Problem

AI agents (Claude Code, OpenClaw, Cursor, etc.) can connect to your Shopify store via the Admin API and edit your theme files directly. No developer needed.

**But without guardrails, they will break your live site.**

We learned this the hard way. Our agent pushed to a theme named "DEV-Kayl" — which was actually the **live theme**. Customers saw a broken store.

## The Solution

`shopify-store-dev` is a safety layer for AI-powered Shopify development:

- 🔒 **Live theme protection** — Auto-detects your live theme and blocks modifications
- 📸 **Git snapshots** — Every change is version-controlled with automatic pre/post commits
- ⏪ **Instant rollback** — Restore any previous version in seconds
- 🚀 **Safe promotion** — Dev → Live with confirmation, snapshot, and rollback command
- 🔌 **Zero dependencies** — Uses `curl` + `git` + `jq` (no Shopify CLI needed)
- 🖥️ **Preview URLs** — Test every change before going live

## Quick Start

### 1. Create a Custom App in Shopify

1. Shopify Admin → **Settings** → **Apps** → **Develop apps**
2. Create app → Configure with `read_themes` + `write_themes` scopes
3. Install → Copy the access token

> 📖 [Full step-by-step guide](references/setup-guide.md) (no technical knowledge needed)

### 2. Initialize

```bash
./scripts/init-store.sh my-store shpat_your_token_here
```

This connects to your store, identifies themes, sets up Git version control, and downloads your dev theme.

### 3. Develop Safely

```bash
# Push changes (auto-snapshots before & after)
./scripts/safe-push.sh templates/index.liquid sections/header.liquid -m "Redesigned homepage"

# Preview your changes
# → https://my-store.myshopify.com/?preview_theme_id=12345

# Something broke? Instant rollback
./scripts/rollback.sh --list
./scripts/rollback.sh --to v3-push

# Ready for production? Promote with safety net
./scripts/promote.sh
```

## How It Works

```
You / Your AI Agent
        │
        ▼
┌─────────────────┐     ┌──────────────────┐
│  safe-push.sh   │────▶│   Dev Theme      │
│  (Git snapshot)  │     │   (unpublished)  │
└─────────────────┘     └──────────────────┘
        │                        │
        │ preview & test         │ promote.sh
        │                        ▼
        │               ┌──────────────────┐
        │               │   Live Theme     │
        │               │   (protected)    │
        │               └──────────────────┘
        │
        ▼
┌─────────────────┐
│   Git History   │ ◀── Every change tracked
│   (rollback)    │     Tags: v1-push, v2-push...
└─────────────────┘
```

## Scripts

| Script | What it does |
|--------|-------------|
| `init-store.sh` | One-time setup — connects store, identifies themes, inits Git |
| `safe-push.sh` | Push files to dev theme with automatic Git snapshots |
| `rollback.sh` | List versions or restore any previous state |
| `promote.sh` | Copy dev theme → live with confirmation + safety net |
| `theme-guard.sh` | Safety gate — blocks operations on live theme |
| `diff.sh` | Compare any two versions |
| `history.sh` | View full change history with tags |

## Safety Rules

These are baked into every script:

1. **Never trust theme names.** A theme named "DEV" can be live. Only the API `role` field matters (`"main"` = live).
2. **Always snapshot before changes.** Every push creates a Git commit before and after.
3. **Dev-only by default.** Scripts refuse to touch the live theme without explicit promotion.
4. **Promote requires confirmation.** You must type `PROMOTE` to push to live.

> 📖 [Full safety documentation](references/safety-rules.md) with real incident details

## Requirements

- `curl` — HTTP requests to Shopify Admin API
- `git` — Version control and rollback
- `jq` — JSON parsing
- **No Shopify CLI needed**

Works on macOS and Linux.

## Install as Agent Skill

### OpenClaw
```bash
# Coming soon to ClawhHub
openclaw skill install shopify-store-dev
```

### Claude Code
```bash
# Coming soon
npx skills add tokenmaster/shopify-store-dev
```

### Manual
```bash
git clone https://github.com/tokenmaster/shopify-store-dev.git
cd shopify-store-dev
chmod +x scripts/*.sh
./scripts/init-store.sh your-store your-token
```

## Who This Is For

- **Ecom store owners** using AI to edit their Shopify themes
- **Agencies** managing multiple Shopify stores with AI agents
- **Developers** who want Git version control on Shopify themes
- **Anyone** who's ever broken a live Shopify store and wished they had a rollback button

## What This Is NOT

This is **not** a Shopify knowledge skill. It doesn't teach your agent Liquid syntax or API patterns. It's the **operational safety layer** — the thing that keeps your agent from breaking your store.

Pair it with a knowledge skill like [shopify-developer-skill](https://github.com/cathrynlavery/shopify-developer-skill) for the full stack.

## API Reference

All scripts use the Shopify Admin REST API. No CLI, no GraphQL, no extra dependencies.

- Auth: `X-Shopify-Access-Token` header
- Rate limit: 2 req/sec (scripts auto-throttle)
- Scopes needed: `read_themes`, `write_themes`

> 📖 [Full API patterns reference](references/api-patterns.md)

## Contributing

Found a bug? Want to add a feature? PRs welcome.

## License

MIT — use it, fork it, ship it.

---

**Built by [Tony Yu](https://twitter.com/itstonyyu) after breaking a live Shopify store with an AI agent. So you don't have to.**

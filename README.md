# Snowflake Cortex Code CLI Slack Bridge

Bidirectional Slack DM bridge for [Cortex Code](https://docs.snowflake.com/en/user-guide/cortex-code/cortex-code-cli) -- get notifications and steer your AI coding agent from your phone.

Full walkthrough and getting started details: [blog on Medium](https://medium.com/snowflake/snowflake-cortex-code-cli-meets-slack-8a3ce0a0630c).

## How It Works

A Socket Mode Slack bot (slack-bolt) runs as a local background daemon. It relays DMs between Slack and Cortex Code sessions via file-based IPC (one inbox file per session). A CoCo cron job polls the inbox and processes messages.

```
Slack DM --> bridge daemon --> inbox_<session>.json --> cron reads --> CoCo processes
CoCo responds --> coco-bridge send --> bridge daemon --> Slack DM
```

## Setup

### Prerequisites

- Python 3.10+
- A Slack app with Socket Mode enabled (Bot Token + App Token)

### Install

```bash
git clone git@github.com:iamontheinet/cortex-code-cli-slack-bridge.git
cd cortex-code-cli-slack-bridge
python3 -m venv .venv && source .venv/bin/activate
pip install -e .
```

### Configure Tokens

**Option A: macOS Keychain (recommended)**

```bash
bin/coco-bridge setup-keychain
```

Migrates tokens from `config.json` into macOS Keychain, or prompts for manual entry.

**Option B: Environment variables**

```bash
export SLACK_APP_TOKEN=xapp-...
export SLACK_BOT_TOKEN=xoxb-...
export SLACK_USER_ID=U...
```

**Option C: Config file**

Create `~/.cortex-slack-bridge/config.json`:

```json
{
  "app_token": "xapp-...",
  "bot_token": "xoxb-...",
  "user_id": "U..."
}
```

Priority: env var > Keychain > config.json.

### Install the Cortex Code Skill

```bash
cp skill/SKILL.md ~/.snowflake/cortex/skills/slack-bridge/SKILL.md
```

Then in Cortex Code, say "slack on" to enable the bridge.

## CLI Reference

```
coco-bridge <command>
```

### Session Lifecycle

| Command | Description |
|---------|-------------|
| `enable-session` | Atomic enable: starts bridge if needed, sends outbound (registers session for DM routing), confirms ready |
| `disable-session` | Atomic disable: clears inbox, sends disconnect notification |

### Bridge Management

| Command | Description |
|---------|-------------|
| `start` | Start the bridge bot in the background |
| `stop` | Stop the bridge bot |
| `status` | Check if the bridge is running |
| `logs` | Tail the bridge log |

### Messaging

| Command | Description |
|---------|-------------|
| `send "message"` | Send a plain notification to Slack |
| `send "msg" --type status` | Send color-coded message (`status` / `success` / `warning` / `error`) |
| `confirm "question"` | Send Approve/Deny buttons, block until response |

### Inbox

| Command | Description |
|---------|-------------|
| `inbox` | Show raw inbox contents |
| `check-inbox` | Double-read poll (read, sleep 30s, read again). Prints JSON if messages found, silent if empty |
| `clear-inbox` | Reset inbox to `[]` |

### History & Auth

| Command | Description |
|---------|-------------|
| `history [N]` | Show last N audit log entries (default: 20) |
| `setup-keychain` | Store Slack tokens in macOS Keychain |
| `clear-keychain` | Remove Slack tokens from macOS Keychain |

## Architecture

- **Bridge daemon** (`cortex_slack_bridge.bridge`): Socket Mode bot, routes incoming DMs to session-scoped inbox files
- **Session routing** (`cortex_slack_bridge.config`): `active_session` file tracks which CoCo session receives DMs. Updated on every outbound `send`
- **Notify** (`cortex_slack_bridge.notify`): Sends messages/confirmations to Slack, registers active session on each call
- **IPC**: `~/.cortex-slack-bridge/inbox_<session_id>.json` -- bridge writes, CoCo reads
- **Audit log**: `~/.cortex-slack-bridge/history.jsonl` -- append-only JSONL of all messages

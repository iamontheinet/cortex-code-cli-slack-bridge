# Cortex Code CLI Slack Bridge

Bidirectional Slack DM bridge for [Cortex Code](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-code) -- get notifications, approve/deny destructive actions, and steer your AI coding agent from your phone.

Read the full writeup: [Building a Bidirectional Slack Bridge for Cortex Code CLI](blog.md)

## Quick Start

```bash
# Clone and install
git clone https://github.com/iamontheinet/cortex-code-cli-slack-bridge.git ~/Apps/cortex-code-cli-slack-bridge
cd ~/Apps/cortex-code-cli-slack-bridge
python3 -m venv .venv
.venv/bin/pip install -e .

# Configure (copy and fill in your Slack tokens)
cp config.json.example ~/.cortex-slack-bridge/config.json
# Edit ~/.cortex-slack-bridge/config.json with your tokens

# Start the bridge
bin/coco-bridge start

# In Cortex Code, say "slack on" to activate
```

## What It Does

- **Notifications** -- send status updates to your Slack DMs
- **Approve/Deny** -- route destructive action confirmations to Slack buttons
- **Free-text replies** -- type instructions from your phone, delivered to the CLI session
- **Multi-session** -- each Cortex Code session gets its own inbox

## Slack App Setup

You need a Slack app with Socket Mode enabled:

1. Create a new Slack app at [api.slack.com/apps](https://api.slack.com/apps)
2. Enable **Socket Mode** and generate an App-Level Token (`xapp-...`)
3. Add Bot Token Scopes: `chat:write`, `im:history`, `im:read`, `im:write`
4. Subscribe to bot events: `message.im`
5. Install the app to your workspace and copy the Bot Token (`xoxb-...`)
6. Find your Slack User ID (click your profile > three dots > Copy member ID)

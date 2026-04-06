# Building a Bidirectional Slack Bridge for Cortex Code CLI

Cortex Code is Snowflake's AI coding agent that runs in your terminal. It reads files, writes code, executes SQL, manages git repos -- the works. But sometimes you kick off a long-running task and walk away. Maybe you're grabbing coffee, maybe you're in a meeting. The agent finishes a step, has a question, and... sits there waiting for you to come back and type something.

That's why I built this Slack bridge. It gives Cortex Code a way to reach you when you're not at the terminal:

- Send you status updates as Slack DMs
- Ask you questions and get free-text replies from your phone
- Present Approve/Deny buttons for decisions the agent wants your input on

You can steer the agent from the couch. "Skip that step and move to the next one." "Use approach #2." "Don't deploy yet." All from Slack.

The whole thing runs as a ~300-line Python sidecar. No servers, no databases, no cloud infra. Just a Slack bot, some JSON files, and a shell wrapper.

## What It Actually Does

Three interaction patterns:

1. **Notifications** -- Cortex Code sends you status updates as Slack DMs. "Feature engineering done. Model training starting." You see them on your phone.

2. **Approve/Deny buttons** -- The bridge includes a `coco-bridge confirm` command that sends a question with Approve and Deny buttons to Slack and blocks until you tap one. This is useful in scripts and automation -- the included demo uses it to simulate destructive action gates. In theory, the skill can instruct the agent to use it before dangerous operations, but in practice the agent doesn't reliably self-gate this way. It's more of a building block for structured workflows than an automatic safety net.

3. **Free-text replies** -- You type a message in the Slack DM. It lands in a session-specific inbox file. Cortex Code's cron job picks it up and treats it as user input. This is the pattern that gets the most real-world use -- steering the agent remotely with instructions like "skip that step" or "use approach #2."

**An important note on bypass safeguards:** This bridge requires Cortex Code's "bypass safeguards" setting to be enabled. Here's why.

By default, Cortex Code has a built-in tool confirmation system -- when the agent wants to run a bash command, execute SQL, or write to a file, it shows an Allow/Deny prompt in the terminal UI. That's a CLI-level feature that the bridge cannot intercept. Those prompts are handled entirely within the terminal.

With bypass safeguards enabled, the built-in tool confirmations are turned off, and the agent runs tools freely. The bridge then gives you a remote communication channel -- you get notifications about what the agent is doing and can send instructions back. The skill instructs the agent to route questions through Slack (via `coco-bridge send`) instead of using the terminal-based `ask_user_question` tool, so you don't need to be at your desk to keep the conversation going.

Here's what the Approve/Deny buttons look like in Slack:

<!-- TODO: Add screenshot of Approve/Deny buttons in Slack DM -->
*[Screenshot: Slack DM showing confirmation prompt with Approve and Deny buttons]*

And the terminal output when the response comes back:

<!-- TODO: Add screenshot of terminal showing "User approved. Executing DROP TABLE..." -->
*[Screenshot: Terminal showing approval received and action executed]*

## Architecture

```
┌─────────────────┐     ┌──────────────────────┐     ┌─────────────┐
│  Cortex Code    │     │   Bridge Bot          │     │   Slack     │
│  CLI Session    │     │   (Socket Mode)       │     │   DM        │
│                 │     │                       │     │             │
│  coco-bridge ───┼────>│  notify.py            │────>│  Message    │
│  send/confirm   │     │  (sends DMs/buttons)  │     │  appears    │
│                 │     │                       │     │             │
│  inbox.json <───┼─────│  bridge.py            │<────│  User taps  │
│  (cron polls)   │     │  (listens for events) │     │  or replies │
└─────────────────┘     └──────────────────────┘     └─────────────┘
```

**Key design decisions:**

- **Socket Mode** -- No public URLs needed. The bot connects outbound to Slack's WebSocket API. Works behind firewalls, no ngrok required.
- **File-based inbox** -- Each Cortex Code session gets its own `inbox_{session_id}.json`. The bridge bot writes to it; the CLI polls it via cron. Dead simple, zero dependencies.
- **Metadata routing** -- Every outbound Slack message includes session metadata. When you tap a button or reply, Slack sends that metadata back. The bridge uses it to write to the correct session's inbox. Multiple sessions, no crosstalk.
- **Sidecar process** -- The bridge bot runs as a background process, started automatically by a SessionStart hook. It's not embedded in Cortex Code -- it's a separate Python process that communicates via the filesystem.

## The Code

The project has four main files. Here's what each does.

### `config.py` -- Configuration and Session Management

Handles paths, tokens, and multi-session routing.

```python
BRIDGE_DIR = Path.home() / ".cortex-slack-bridge"
INBOX_FILE = BRIDGE_DIR / "inbox.json"
PID_FILE = BRIDGE_DIR / "bridge.pid"
```

Tokens come from environment variables first (`SLACK_BRIDGE_APP_TOKEN`, `SLACK_BRIDGE_BOT_TOKEN`), falling back to a JSON config file at `~/.cortex-slack-bridge/config.json`. The config file approach is easier for local dev; env vars are better for anything automated.

Session management is minimal: `get_session_inbox()` returns the inbox path for a session ID, and `set_active_session()` / `get_active_session()` track which session the bridge should route messages to when there's no metadata to go on.

### `bridge.py` -- The Socket Mode Bot

This is the long-running process. It connects to Slack via Socket Mode and listens for two things:

**DM messages** -- When you type in the Slack DM, it captures the text and writes it to the active session's inbox:

```python
@app.event("message")
def handle_dm(event, say):
    user = event.get("user")
    if subtype or user != target_user:
        return
    _append_inbox({
        "type": "reply",
        "text": event.get("text", ""),
        ...
    })
    say("Message sent to CoCo CLI. Awaiting response...")
```

**Button clicks** -- Approve and Deny buttons trigger action handlers that extract the `confirmation_id` from the block ID and the `session_id` from message metadata, then write the response to the correct inbox:

```python
@app.action("confirm_approve")
def handle_approve(ack, body, client):
    ack()
    action_id = _extract_confirmation_id(body)
    session_id = _extract_session_id(body, client)
    _append_inbox({
        "type": "confirmation",
        "confirmation_id": action_id,
        "response": "approved",
        ...
    }, session_id=session_id)
    _update_confirmation_message(client, body, "Approved ✓")
```

After a button click, the original message gets updated to show the result (replacing the buttons with "Approved ✓" or "Denied ✗"). This prevents double-clicks and gives you visual confirmation.

### `notify.py` -- Sending Messages and Confirmations

This is the outbound side. Two main functions:

**`send_message()`** -- Sends a plain DM or a color-coded message (blue for status, green for success, yellow for warnings, red for errors). Every message includes session metadata so replies route back correctly:

```python
metadata = {
    "event_type": "cortex_bridge",
    "event_payload": {"session_id": sid},
}
```

**`send_confirmation()`** -- Sends Approve/Deny buttons and then polls the inbox waiting for a response. This is a blocking call -- it sits in a loop checking the inbox file until the user clicks a button or the timeout expires:

```python
def send_confirmation(question, *, confirmation_id, timeout=300):
    # Send buttons to Slack
    send_message(question, blocks=[...buttons...])
    # Poll inbox until response arrives
    deadline = time.time() + timeout
    while time.time() < deadline:
        result = _pop_confirmation(confirmation_id)
        if result:
            return result["response"]  # "approved" or "denied"
        time.sleep(2)
    raise TimeoutError(...)
```

### `bin/coco-bridge` -- The Shell Wrapper

A bash script that makes everything easy to use from Cortex Code's skill system:

```bash
coco-bridge start              # Start the bridge bot
coco-bridge stop               # Stop it
coco-bridge status             # Check if running
coco-bridge send "message"     # Send a DM
coco-bridge send "msg" --type success  # Color-coded
coco-bridge confirm "question" # Approve/Deny buttons
coco-bridge inbox              # Read inbox contents
coco-bridge logs               # Tail the log file
```

It auto-detects the project's virtualenv, manages the PID file, and dispatches to the Python modules.

## How It Integrates with Cortex Code

This project exists because of Cortex Code's hook system, and it's worth pausing to appreciate how much that unlocks.

### The Hook System

Cortex Code has a lifecycle hook system defined in `~/.snowflake/cortex/hooks.json`. You can register shell commands that fire at specific points:

- **SessionStart** -- runs when a new session begins (before the agent does anything)
- **PostToolUse** -- fires after every tool call (bash, file write, SQL execution, etc.)
- **UserPromptSubmit** -- fires when the user sends a message
- **Stop** -- fires when the session ends
- **SubagentStop** -- fires when a background agent completes

Each hook is a shell command with a configurable timeout. The stdout from SessionStart hooks gets passed to the agent as context, which is how the bridge tells Cortex Code "hey, I'm running, ask the user if they want Slack enabled."

This is a big deal. It means you can build sidecar applications that plug into Cortex Code's lifecycle without modifying Cortex Code itself. The Slack bridge uses SessionStart to auto-launch. But you could just as easily build:

- A PostToolUse hook that logs every tool call to a database (audit trail)
- A UserPromptSubmit hook that captures conversation history (flight recorder)
- A Stop hook that sends a session summary to Slack or email

The hook system turns Cortex Code from a closed tool into an extensible platform. This bridge is just one example of what's possible.

### 1. SessionStart Hook

The bridge uses a SessionStart hook in `~/.snowflake/cortex/hooks.json` that runs on every new session. It checks if the bridge bot is running and starts it if not:

```bash
#!/usr/bin/env bash
PROJECT_DIR="$HOME/Apps/cortex-code-cli-slack-bridge"
PYTHON="$PROJECT_DIR/.venv/bin/python"

if ! _is_running; then
    nohup "$PYTHON" -m cortex_slack_bridge.bridge >> "$LOG_FILE" 2>&1 &
fi
```

### 2. Cortex Code Skill

Cortex Code has a skill system that lets you teach the agent new behaviors via markdown files. A skill is just a `SKILL.md` file in `~/.snowflake/cortex/skills/<name>/` with frontmatter (name, description, trigger phrases, required tools) and a body that explains how the agent should behave.

The Slack bridge skill (`~/.snowflake/cortex/skills/slack-bridge/SKILL.md`) defines:

- **Trigger phrases** -- "slack on", "enable slack", "/slack", etc.
- **Activation flow** -- what to do when the user opts in
- **Message routing** -- how to handle inbox entries, when to use notifications vs. confirmations
- **Deactivation** -- how "slack off" tears down the polling

When you say "slack on", the skill instructs the agent to:

1. Create a session-scoped cron job that polls the inbox every minute
2. Send an activation message to Slack
3. Start routing questions and confirmations through Slack instead of the terminal

The cron pattern here is worth calling out. Cortex Code's `cron_create` tool lets you schedule prompts that fire on a schedule -- and they're session-scoped, meaning they die when the session ends. The bridge uses this as a heartbeat: every minute, a "Slack inbox check" prompt fires. The skill tells the agent to read the inbox file, process any messages silently if empty, and handle them if not. It's a clever way to give an agent a polling loop without any background threads or watchers -- just a cron job and a JSON file.

The skill also handles "slack off" to disable the bridge mid-session, and defines when to use notifications vs. confirmations vs. free-text questions.

## Setting It Up

### Prerequisites

- Python 3.10+
- A Slack workspace where you can install apps
- [Cortex Code CLI](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-code)

### Create the Slack App

1. Go to [api.slack.com/apps](https://api.slack.com/apps) and create a new app
2. Under **Socket Mode**, enable it and create an App-Level Token with `connections:write` scope. Save the `xapp-...` token.
3. Under **OAuth & Permissions**, add these Bot Token Scopes:
   - `chat:write` -- send DMs
   - `im:history` -- read DM history
   - `im:read` -- view DM channels
   - `im:write` -- open DM channels
4. Under **Event Subscriptions**, enable events and subscribe to the `message.im` bot event
5. Under **Interactivity & Shortcuts**, enable interactivity (no URL needed for Socket Mode)
6. Install the app to your workspace. Copy the Bot User OAuth Token (`xoxb-...`).
7. Find your Slack User ID: click your profile picture in Slack, click the three dots, "Copy member ID"

### Install the Bridge

```bash
git clone https://github.com/iamontheinet/cortex-code-cli-slack-bridge.git \
    ~/Apps/cortex-code-cli-slack-bridge
cd ~/Apps/cortex-code-cli-slack-bridge
python3 -m venv .venv
.venv/bin/pip install -e .
```

### Configure Tokens

```bash
mkdir -p ~/.cortex-slack-bridge
cp config.json.example ~/.cortex-slack-bridge/config.json
```

Edit `~/.cortex-slack-bridge/config.json` with your actual tokens:

```json
{
  "app_token": "xapp-1-A0...",
  "bot_token": "xoxb-...",
  "user_id": "U02M..."
}
```

### Start and Test

```bash
# Start the bridge
bin/coco-bridge start

# Send a test message
bin/coco-bridge send "Hello from the bridge!"

# Test confirmation buttons
bin/coco-bridge confirm "Test confirmation -- approve or deny?" --id test-1 --timeout 60
```

Check your Slack DMs. You should see the messages and buttons.

### Wire Up the SessionStart Hook

Add this to `~/.snowflake/cortex/hooks.json` so the bridge auto-starts with every Cortex Code session:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/Users/YOUR_USERNAME/.cortex-slack-bridge/start-hook.sh",
            "timeout": 10,
            "enabled": true
          }
        ]
      }
    ]
  }
}
```

Copy the start hook script:

```bash
cp demo-start-hook.sh ~/.cortex-slack-bridge/start-hook.sh
chmod +x ~/.cortex-slack-bridge/start-hook.sh
```

## The Demo

The repo includes `demo.sh` which walks through all three interaction patterns:

1. **Approve** -- Asks to drop a staging table. You tap Approve in Slack.
2. **Deny** -- Asks to deploy a model to production. You tap Deny.
3. **Free-text** -- Sends a status update and asks for instructions. You type a reply.

```bash
bash ~/Apps/cortex-code-cli-slack-bridge/demo.sh
```

It's interactive -- the script pauses between scenarios so you can follow along on your phone.

## Things I'd Do Differently

A few rough edges and ideas for v2:

- **Polling is crude** -- The cron job checks the inbox every minute. A WebSocket or file watcher would be more responsive, but the simplicity of cron-based polling won out for v1.
- **No encryption** -- Inbox files are plain JSON on disk. The tokens in config.json are also plain text. For a personal tool on your own machine this is fine; for anything shared, you'd want keychain integration or Cortex secret injection.
- **Single user only** -- The bridge is hardcoded to one Slack user ID. Multi-user support would need a mapping layer.
- **No message history** -- Inbox entries are consumed and deleted. If you wanted an audit trail, you'd log them somewhere persistent.

## Wrapping Up

The whole project is ~300 lines of Python plus a shell wrapper. It turns Cortex Code from a "sit at your desk" tool into something you can supervise from your phone. The Approve/Deny pattern is especially useful -- you can kick off a big migration, walk away, and approve each destructive step from Slack as the agent reaches it.

One last thing: this blog post was itself written and iterated on via the Slack bridge. I kicked off the work in Cortex Code, walked away from my laptop, and reviewed the draft from my phone. When I wanted changes -- "add a section on the hook system", "clarify the bypass safeguards requirement" -- I typed them into the Slack DM. Cortex Code picked them up, made the edits, committed, pushed, and sent me a confirmation. The whole review loop happened without me touching the terminal. If that's not a good dogfood moment, I don't know what is.

The code is at [github.com/iamontheinet/cortex-code-cli-slack-bridge](https://github.com/iamontheinet/cortex-code-cli-slack-bridge). Clone it, plug in your Slack tokens, and try the demo.

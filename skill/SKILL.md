---
name: slack-bridge
description: "Bidirectional Slack DM bridge for remote notifications and confirmations. Use when: user says enable slack, start slack, activate slack, slack on, /slack, disable slack, stop slack, slack off, pause slack, pause, brb, resume slack, resume, unpause, back, I'm back. Also use for: sending notifications to user's phone, requesting remote approval, checking for Slack replies. Triggers: enable slack, start slack, activate slack, slack on, /slack, disable slack, stop slack, deactivate slack, slack off, pause slack, pause, brb, take a break, hold on, resume slack, resume, unpause, back, I'm back, notify, bridge, remote, phone, DM, confirm remotely."
tools: ["bash", "cron_create", "cron_delete", "cron_list"]
---

# Slack Bridge

Bidirectional Slack DM bridge — send notifications, request confirmations with Approve/Deny buttons, and receive replies from the user's phone.

**This bridge is opt-in per session.** The bot process runs in the background (started by the SessionStart hook), but Slack interaction is only activated when the user explicitly asks.

## SessionStart Prompt

When the SessionStart hook fires, it outputs a message telling you to ask the user if they want Slack enabled. When you see this, use `ask_user_question` with a simple Yes/No:

- Question: "Enable Slack notifications for this session?"
- Header: "Slack Bridge"
- Options: "Yes" (description: "Activate Slack DM bridge — get notifications and respond from your phone") and "No" (description: "Skip — you can say 'slack on' anytime to enable later")

If user picks "Yes", proceed with the enable flow below. If "No", do nothing.

## Enabling Slack for This Session

When the user says "enable slack", "start slack", "activate slack", "slack on", "/slack", or answers "Yes" to the SessionStart prompt, do **exactly these 2 steps in order**:

**Step 1 — Create the inbox polling cron (MANDATORY FIRST):**
```
cron_create with cron "*/1 * * * *" and prompt:
"Slack inbox check: Run ~/Apps/cortex-code-cli-slack-bridge/bin/coco-bridge check-inbox — if output is empty, do nothing, completely silent. If JSON entries are printed, process each entry: for reply type treat text as user input and handle the request, then send a concise response back via ~/Apps/cortex-code-cli-slack-bridge/bin/coco-bridge send, then run ~/Apps/cortex-code-cli-slack-bridge/bin/coco-bridge clear-inbox"
```

**STOP: Verify you received a job ID back from cron_create before continuing. If you did not get a job ID, call cron_create again.**

**Step 2 — Enable the session (single command):**
```bash
~/Apps/cortex-code-cli-slack-bridge/bin/coco-bridge enable-session
```
This command atomically: ensures the bridge daemon is running, sends an outbound "Slack bridge active" message (which registers this session for inbound DM routing), and prints confirmation.

**That's it. Do NOT add extra steps. Do NOT skip either step.**

**Do NOT set up cron or send Slack messages unless the user has opted in.**

**Polling latency reference:**
- **Normal mode** (`*/1` cron + double-read in check-inbox): ~30s effective latency
- **Pause mode** (`*/5` cron + single read): ~5 min latency, only checks for resume keywords
- **Stop/disable**: No polling at all, inbox cleared

## Pausing Slack

When the user says "pause slack", "pause", "brb", "take a break", or "hold on" (from CLI or Slack):

1. List active crons with `cron_list` and delete the "Slack inbox check" cron with `cron_delete`
2. Create a slow heartbeat cron:
```
cron_create with cron "*/5 * * * *" and prompt:
"Slack pause heartbeat: The bridge is PAUSED. Run ~/Apps/cortex-code-cli-slack-bridge/bin/coco-bridge inbox — if output is [] do nothing, completely silent. If entries exist, check ONLY for resume keywords (resume, back, unpause, I'm back) in the text field. If a resume keyword is found, trigger the full resume flow: delete this heartbeat cron, recreate the normal */1 inbox polling cron, run ~/Apps/cortex-code-cli-slack-bridge/bin/coco-bridge send 'Slack bridge resumed', process ALL queued messages, then run ~/Apps/cortex-code-cli-slack-bridge/bin/coco-bridge clear-inbox. If no resume keywords, do nothing — leave messages queued, completely silent."
```
3. Send pause notification:
```bash
~/Apps/cortex-code-cli-slack-bridge/bin/coco-bridge send "Slack bridge paused. Say 'resume' here or in the CLI when you're ready."
```
4. Confirm to the user: "Slack bridge paused — inbox checks stopped. A slow heartbeat runs every 5 min to watch for 'resume' from Slack."

**Do NOT clear the inbox file when pausing.** Messages accumulate and will be picked up on resume.

## Resuming Slack

Resume can be triggered from **CLI** (user says "resume") or **Slack** (user sends "resume", picked up by heartbeat). Either way:

1. List active crons with `cron_list` and delete any "Slack pause heartbeat" cron with `cron_delete`
2. Create the normal inbox polling cron (same as enable step 1):
```
cron_create with cron "*/1 * * * *" and prompt:
"Slack inbox check: Run ~/Apps/cortex-code-cli-slack-bridge/bin/coco-bridge check-inbox — if output is empty, do nothing, completely silent. If JSON entries are printed, process each entry: for reply type treat text as user input and handle the request, then send a concise response back via ~/Apps/cortex-code-cli-slack-bridge/bin/coco-bridge send, then run ~/Apps/cortex-code-cli-slack-bridge/bin/coco-bridge clear-inbox"
```
3. Send resume notification:
```bash
~/Apps/cortex-code-cli-slack-bridge/bin/coco-bridge send "Slack bridge resumed"
```
4. Confirm to the user: "Slack bridge resumed — inbox checks active again."

## Disabling Slack Mid-Session

When the user says "disable slack", "stop slack", "deactivate slack", or "slack off":

1. List active crons with `cron_list` and delete the "Slack inbox check" cron with `cron_delete`
2. Disable the session (single command):
```bash
~/Apps/cortex-code-cli-slack-bridge/bin/coco-bridge disable-session
```
This command atomically: clears the inbox, sends "Slack bridge off" to Slack, and prints confirmation.

3. Confirm to the user: "Slack bridge disabled. Say 'slack on' to reactivate."

After disabling, do NOT send Slack notifications or poll the inbox until the user opts back in.

## Commands

All commands use the wrapper at `~/Apps/cortex-code-cli-slack-bridge/bin/coco-bridge`:

### Session lifecycle
```bash
coco-bridge enable-session     # Atomic enable (start + register + notify)
coco-bridge disable-session    # Atomic disable (clear + notify)
coco-bridge check-inbox        # Double-read inbox (30s sleep); prints JSON or nothing
coco-bridge clear-inbox        # Clear session inbox file
```

### Send a notification
```bash
~/Apps/cortex-code-cli-slack-bridge/bin/coco-bridge send "Task completed successfully"
```

### Send confirmation with Approve/Deny buttons
```bash
~/Apps/cortex-code-cli-slack-bridge/bin/coco-bridge confirm "Deploy to production?" --id deploy-123
```
This blocks until the user clicks Approve or Deny. Prints `approved` or `denied` to stdout.

### Bridge management
```bash
~/Apps/cortex-code-cli-slack-bridge/bin/coco-bridge start    # Start bot (usually auto-started by hook)
~/Apps/cortex-code-cli-slack-bridge/bin/coco-bridge stop     # Stop bot
~/Apps/cortex-code-cli-slack-bridge/bin/coco-bridge status   # Check if running
~/Apps/cortex-code-cli-slack-bridge/bin/coco-bridge logs     # Tail bridge logs
~/Apps/cortex-code-cli-slack-bridge/bin/coco-bridge inbox    # Show raw inbox contents
~/Apps/cortex-code-cli-slack-bridge/bin/coco-bridge history  # Show last 20 history entries
```

## When to Notify

Send Slack notifications when:
- A long-running task completes or fails
- You need user confirmation for a destructive or important action
- You have a question and the user hasn't responded in the terminal
- A significant milestone is reached in multi-step work

## Restoring Slack on Session Resume

**CRITICAL**: The inbox polling cron is session-scoped — it dies when the session ends or context resets. When a session resumes, the bridge daemon is still running but the cron is gone.

When the SessionStart hook detects a prior inbox file for this session, it outputs a message telling you to auto-enable. **You MUST immediately run the full enable flow** (step 1: cron_create, step 2: coco-bridge enable-session) — do NOT wait for the user to say "slack on".

Even if the hook doesn't fire (e.g., context continuation), if the conversation summary mentions "Slack bridge active" or "Slack inbox polling cron", you MUST run the enable flow as your first action.

## Proactive Updates on Session Resume

When a session resumes from a context summary and the summary indicates pending/in-progress work:

1. **First, restore Slack** (full enable flow above)
2. Complete the carried-over work
3. **Immediately send a completion update** via `coco-bridge send` — do NOT wait for the user to ask

## When to Use Confirmations

Use `confirm` (Approve/Deny buttons) for:
- Destructive operations (DROP, DELETE, overwrite)
- Deploying to production
- Making irreversible changes
- Any action where the user explicitly asked to be consulted remotely

## Tool Confirmations via Slack

**When Slack is enabled and the agent needs user confirmation**, send it to Slack so the user can respond from their phone:

```bash
~/Apps/cortex-code-cli-slack-bridge/bin/coco-bridge confirm "Run DROP TABLE staging.temp_data?" --id drop-temp-data
```

Use this whenever the agent would normally pause and ask the user in the CLI.

## Questions via Slack

**When Slack is enabled, do NOT use `ask_user_question`.** That renders interactive UI in the CLI requiring the user to be at the terminal. Instead:

```bash
~/Apps/cortex-code-cli-slack-bridge/bin/coco-bridge send "Which approach? (1) Simple cron polling (2) Background watcher (3) WebSocket — reply with 1, 2, or 3"
```

Format questions clearly with numbered options so the user can reply briefly from their phone.

## Responding to Slack Messages

When processing a message from Slack (via the inbox), **always send your response back to Slack**:

```bash
~/Apps/cortex-code-cli-slack-bridge/bin/coco-bridge send "Your response text here"
```

Keep Slack responses concise — 2-3 sentences max. The user is on their phone.

## Inbox Format

```json
[
  {
    "type": "reply",
    "text": "user's message",
    "user": "U02M8RTD1HT",
    "ts": "1234567890.123456",
    "received_at": 1234567890.123
  },
  {
    "type": "confirmation",
    "confirmation_id": "deploy-123",
    "response": "approved",
    "user": "U02M8RTD1HT",
    "received_at": 1234567890.123
  }
]
```

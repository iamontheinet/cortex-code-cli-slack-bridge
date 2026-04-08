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

When the user says "enable slack", "start slack", "activate slack", "slack on", "/slack", or answers "Yes" to the SessionStart prompt, do the following:

1. Set up inbox polling cron:
```
cron_create with cron "*/1 * * * *" and prompt:
"Slack inbox check: You MUST run this Bash command FIRST — do NOT skip it or respond without running it: cat ~/.cortex-slack-bridge/inbox_${CORTEX_SESSION_ID}.json — if the output is [] or file not found, run: sleep 30 && cat ~/.cortex-slack-bridge/inbox_${CORTEX_SESSION_ID}.json — if still [] after second read, do nothing, completely silent. If entries found on either read, process them: for reply type treat text as user input, send response back via coco-bridge send, then clear with: echo '[]' > ~/.cortex-slack-bridge/inbox_${CORTEX_SESSION_ID}.json"
```

2. Only AFTER the cron is created, send the activation message to Slack:
```bash
~/Apps/cortex-code-cli-slack-bridge/bin/coco-bridge send "Slack bridge active"
```

3. Confirm to the user: "Slack bridge enabled. You'll get notifications here and can respond from your phone."

**Cron handler ("Slack inbox check"):** You MUST use the Bash tool to run `cat ~/.cortex-slack-bridge/inbox_${CORTEX_SESSION_ID}.json` — never skip this tool call. If output is `[]` or file not found, run `sleep 30 && cat ~/.cortex-slack-bridge/inbox_${CORTEX_SESSION_ID}.json`. If still empty after the second read, do nothing — completely silent, no output. If it has entries (on either read), process them (reply type: treat text as user input; confirmation type: use confirmation_id and response), send a concise response back to Slack via `coco-bridge send`, then clear: `echo '[]' > ~/.cortex-slack-bridge/inbox_${CORTEX_SESSION_ID}.json`

Each session gets its own inbox file (`inbox_{session_id}.json`), so multiple sessions don't steal each other's messages. The bridge bot routes replies back to the correct session using metadata embedded in outbound Slack messages.

**Do NOT set up cron or send Slack messages unless the user has opted in.**

## Pausing Slack

When the user says "pause slack", "pause", "brb", "take a break", or "hold on" (from CLI or Slack), do the following:

1. List active crons with `cron_list` and delete the "Slack inbox check" cron with `cron_delete`
2. Create a slow heartbeat cron that ONLY watches for resume keywords:
```
cron_create with cron "*/5 * * * *" and prompt:
"Slack pause heartbeat: The bridge is PAUSED. Run: cat ~/.cortex-slack-bridge/inbox_${CORTEX_SESSION_ID}.json — if the output is [] or file not found, do nothing, completely silent. If entries exist, check ONLY for resume keywords (resume, back, unpause, I'm back) in the text field. If a resume keyword is found, trigger the full resume flow: delete this heartbeat cron, recreate the normal */1 inbox polling cron, send 'Slack bridge resumed' via coco-bridge send, process ALL queued messages (including non-resume ones), then clear the inbox. If entries exist but NONE contain resume keywords, do nothing — leave them queued, completely silent."
```
3. Send a pause message to Slack:
```bash
~/Apps/cortex-code-cli-slack-bridge/bin/coco-bridge send "Slack bridge paused. Say 'resume' here or in the CLI when you're ready."
```
4. Confirm to the user: "Slack bridge paused — inbox checks stopped. A slow heartbeat runs every 5 min to watch for 'resume' from Slack. You can also say 'resume' here in the CLI."

**Do NOT clear the inbox file when pausing.** Messages that arrive while paused accumulate in the inbox and will be picked up on resume.

## Resuming Slack

Resume can be triggered from **CLI** (user says "resume" in the terminal) or **Slack** (user sends "resume" as a DM, picked up by the pause heartbeat). Either way, do the following:

1. List active crons with `cron_list` and delete any "Slack pause heartbeat" cron with `cron_delete`
2. Set up the normal inbox polling cron (same as the enable flow):
```
cron_create with cron "*/1 * * * *" and prompt:
"Slack inbox check: You MUST run this Bash command FIRST — do NOT skip it or respond without running it: cat ~/.cortex-slack-bridge/inbox_${CORTEX_SESSION_ID}.json — if the output is [] or file not found, run: sleep 30 && cat ~/.cortex-slack-bridge/inbox_${CORTEX_SESSION_ID}.json — if still [] after second read, do nothing, completely silent. If entries found on either read, process them: for reply type treat text as user input, send response back via coco-bridge send, then clear with: echo '[]' > ~/.cortex-slack-bridge/inbox_${CORTEX_SESSION_ID}.json"
```
3. Send a resume message to Slack:
```bash
~/Apps/cortex-code-cli-slack-bridge/bin/coco-bridge send "Slack bridge resumed"
```
4. Confirm to the user: "Slack bridge resumed — inbox checks active again."

Any messages that queued during the pause (including the resume message itself) will be processed on the first normal cron cycle after resume.

## Disabling Slack Mid-Session

When the user says "disable slack", "stop slack", "deactivate slack", or "slack off", do the following:

1. List active crons with `cron_list` and delete the "Slack inbox check" cron with `cron_delete`
2. Clear the inbox:
```bash
echo '[]' > ~/.cortex-slack-bridge/inbox_${CORTEX_SESSION_ID}.json
```
3. Send a deactivation message to Slack:
```bash
~/Apps/cortex-code-cli-slack-bridge/bin/coco-bridge send "Slack bridge off"
```
4. Confirm to the user: "Slack bridge disabled. Say 'slack on' to reactivate."

After disabling, do NOT send Slack notifications or poll the inbox until the user opts back in. The user can re-enable at any time by saying "enable slack" again.

## Commands

All commands use the wrapper at `~/Apps/cortex-code-cli-slack-bridge/bin/coco-bridge`:

### Send a notification
```bash
~/Apps/cortex-code-cli-slack-bridge/bin/coco-bridge send "Task completed successfully"
```

### Send confirmation with Approve/Deny buttons
```bash
~/Apps/cortex-code-cli-slack-bridge/bin/coco-bridge confirm "Deploy to production?" --id deploy-123
```
This blocks until the user clicks Approve or Deny. Prints `approved` or `denied` to stdout.

### Check for replies
```bash
~/Apps/cortex-code-cli-slack-bridge/bin/coco-bridge inbox
```
Returns JSON array of messages. Each entry has:
- `type`: "reply" (free text DM) or "confirmation" (button click)
- `text`: message content (for replies)
- `confirmation_id` and `response`: "approved"/"denied" (for confirmations)

### Bridge management
```bash
~/Apps/cortex-code-cli-slack-bridge/bin/coco-bridge start    # Start bot (usually auto-started by hook)
~/Apps/cortex-code-cli-slack-bridge/bin/coco-bridge stop     # Stop bot
~/Apps/cortex-code-cli-slack-bridge/bin/coco-bridge status   # Check if running
~/Apps/cortex-code-cli-slack-bridge/bin/coco-bridge logs     # Tail bridge logs
~/Apps/cortex-code-cli-slack-bridge/bin/coco-bridge history   # Show last 20 history entries
~/Apps/cortex-code-cli-slack-bridge/bin/coco-bridge history 50  # Show last 50 entries
```

## When to Notify

Send Slack notifications when:
- A long-running task completes or fails
- You need user confirmation for a destructive or important action
- You have a question and the user hasn't responded in the terminal
- A significant milestone is reached in multi-step work

## When to Use Confirmations

Use `confirm` (Approve/Deny buttons) for:
- Destructive operations (DROP, DELETE, overwrite)
- Deploying to production
- Making irreversible changes
- Any action where the user explicitly asked to be consulted remotely

## Tool Confirmations via Slack

**When Slack is enabled and the agent needs user confirmation for a tool action** (e.g., SQL execution, file changes, destructive operations), send the confirmation to Slack with Approve/Deny buttons so the user can respond from their phone:

```bash
~/Apps/cortex-code-cli-slack-bridge/bin/coco-bridge confirm "Run DROP TABLE staging.temp_data?" --id drop-temp-data
```

This lets the user work "offline" — the agent sends the confirmation, waits for the button click, and continues based on the response. The user doesn't need to be at the terminal.

Use this pattern whenever the agent would normally pause and ask the user in the CLI. With Slack on, route that question to Slack instead so the session isn't blocked waiting for terminal input.

## Questions via Slack

**When Slack is enabled, do NOT use `ask_user_question` for questions.** That tool renders interactive UI in the CLI which requires the user to be at the terminal. Instead, send the question as a plain text Slack message:

```bash
~/Apps/cortex-code-cli-slack-bridge/bin/coco-bridge send "Which approach? (1) Simple cron polling (2) Background watcher (3) WebSocket — reply with 1, 2, or 3"
```

The user replies as a free-text DM, which arrives in the inbox on the next cron cycle. Format questions clearly with numbered options so the user can reply briefly from their phone.

## Responding to Slack Messages

When processing a message that came FROM Slack (via the inbox watcher), **always send your response back to Slack** in addition to displaying it in the CLI. After generating your response, run:

```bash
~/Apps/cortex-code-cli-slack-bridge/bin/coco-bridge send "Your response text here"
```

Keep Slack responses concise — summarize in 2-3 sentences max. The user is reading on their phone. If the response involves code or long output, send a brief summary to Slack and note that full details are in the CLI session.

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

After processing inbox entries, clear the file:
```bash
echo '[]' > ~/.cortex-slack-bridge/inbox_${CORTEX_SESSION_ID}.json
```

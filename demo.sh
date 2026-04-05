#!/usr/bin/env bash
# demo.sh — Cortex Code Slack Bridge Demo
# Run: bash ~/Apps/cortex-code-cli-slack-bridge/demo.sh
#
# Three scenarios demonstrating bidirectional Slack DM interaction:
#   1. Approve — destructive action (DROP TABLE)
#   2. Deny   — production deployment blocked
#   3. Free-text — remote instructions from phone

set -euo pipefail

BRIDGE="$HOME/Apps/cortex-code-cli-slack-bridge/bin/coco-bridge"
INBOX="$HOME/.cortex-slack-bridge/inbox.json"

bold()  { printf "\033[1m%s\033[0m\n" "$1"; }
green() { printf "\033[32m%s\033[0m\n" "$1"; }
red()   { printf "\033[31m%s\033[0m\n" "$1"; }
dim()   { printf "\033[2m%s\033[0m\n" "$1"; }

clear_inbox() { echo '[]' > "$INBOX"; }

poll_inbox() {
    local timeout=${1:-60}
    for _ in $(seq 1 "$timeout"); do
        local inbox
        inbox=$("$BRIDGE" inbox 2>/dev/null)
        if [ "$inbox" != "[]" ]; then
            echo "$inbox"
            return 0
        fi
        sleep 1
    done
    echo "[]"
    return 1
}

# ── Preflight ──────────────────────────────────────────────
bold "Cortex Code Slack Bridge — Live Demo"
echo ""

dim "Checking bridge status..."
if ! "$BRIDGE" status 2>/dev/null | grep -q "running"; then
    dim "Starting bridge..."
    "$BRIDGE" start
fi
green "Bridge is running."
clear_inbox
echo ""

dim "Press Enter to begin..."
read -r

# ── Intro ──────────────────────────────────────────────────
"$BRIDGE" send ":robot_face: *Cortex Code Slack Bridge — Live Demo*

Three scenarios coming up:
1. Approve a destructive action
2. Deny a production deployment
3. Send free-text instructions

Watch for the prompts!" > /dev/null

echo ""
bold "═══════════════════════════════════════════"
bold "  SCENARIO 1: Approve a Destructive Action"
bold "═══════════════════════════════════════════"
echo ""
echo "Asking permission to drop a staging table..."
echo "→ Tap APPROVE in Slack"
echo ""

result=$("$BRIDGE" confirm \
    "DROP TABLE DASH_DB.STAGING.EVENTS_TEMP — this staging table has 2.3M rows from last week's ETL test. Safe to clean up?" \
    --id demo-drop-staging \
    --timeout 120 2>&1)

if [ "$result" = "approved" ]; then
    green "✓ User approved. Executing DROP TABLE... (simulated)"
    "$BRIDGE" send ":white_check_mark: *Scenario 1 complete* — DROP TABLE approved and executed." > /dev/null
else
    red "✗ User denied. Skipping."
    "$BRIDGE" send ":x: *Scenario 1* — User denied the DROP." > /dev/null
fi

echo ""
dim "Press Enter for Scenario 2..."
read -r

# ── Scenario 2 ─────────────────────────────────────────────
echo ""
bold "═══════════════════════════════════════════"
bold "  SCENARIO 2: Deny a Production Deployment"
bold "═══════════════════════════════════════════"
echo ""
echo "Asking permission to deploy model to production..."
echo "→ Tap DENY in Slack"
echo ""

result=$("$BRIDGE" confirm \
    "Ready to deploy ML model MODEL_BEHAVIORAL_ONLY to DASH_DB.PROD.MODELS — this replaces the current production model. Proceed?" \
    --id demo-deploy-prod \
    --timeout 120 2>&1)

if [ "$result" = "approved" ]; then
    green "✓ User approved. Deploying... (simulated)"
    "$BRIDGE" send ":rocket: *Scenario 2* — Deployment approved." > /dev/null
else
    red "✗ User denied. Standing down — no deployment."
    "$BRIDGE" send ":no_entry_sign: *Scenario 2 complete* — Production deployment blocked by user." > /dev/null
fi

echo ""
dim "Press Enter for Scenario 3..."
read -r

# ── Scenario 3 ─────────────────────────────────────────────
echo ""
bold "═══════════════════════════════════════════"
bold "  SCENARIO 3: Free-Text Remote Instructions"
bold "═══════════════════════════════════════════"
echo ""
echo "Sending a status update and asking for next steps..."
echo "→ Type a reply in Slack (any text)"
echo ""

clear_inbox

"$BRIDGE" send ":memo: *Status update from Cortex Code*
- Feature engineering: done (5 tables created)
- Model training: done (3 models evaluated)
- Cross-validation: done (winner selected)
- Production deployment: on hold

What should I work on next? Reply here with instructions." > /dev/null

echo "Waiting for your text reply..."
reply=$(poll_inbox 120)

if [ "$reply" = "[]" ]; then
    red "No reply received within 2 minutes."
else
    text=$(echo "$reply" | python3 -c "import sys,json; entries=json.load(sys.stdin); print(entries[0]['text'] if entries else 'No message')")
    echo ""
    green "✓ Received instruction: \"$text\""
    "$BRIDGE" send ":rocket: *Scenario 3 complete* — Received your instruction: \"$text\"" > /dev/null
fi

clear_inbox

# ── Wrap-up ────────────────────────────────────────────────
echo ""
bold "═══════════════════════════════════════════"
bold "  DEMO COMPLETE"
bold "═══════════════════════════════════════════"
echo ""
echo "Three interaction patterns demonstrated:"
echo "  1. Approve — safety gate for destructive operations"
echo "  2. Deny   — agent respects rejection, stands down"
echo "  3. Text   — remote steering from your phone"
echo ""
dim "All interactions happened via Slack DM while Cortex Code ran locally."

"$BRIDGE" send ":tada: *Demo complete!*

Three patterns demonstrated:
1. *Approve* — safety gate for destructive ops
2. *Deny* — blocked production deployment
3. *Free-text* — remote instructions from phone

All from Slack on your phone while Cortex Code runs on your machine." > /dev/null

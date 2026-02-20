---
description: Safe local text actions for MiloOverlay using selected-text rewrite preview + explicit apply.
---

# Milo Desktop Actions

Use this skill when the user asks to rewrite, polish, shorten, expand, or insert text in their current desktop app.

## Goal

Enable this flow:
1. Read selected text from active app.
2. Propose rewrite preview.
3. Wait for explicit confirmation.
4. Apply rewrite to the same selection.

Never apply edits without explicit confirmation.

## Bridge Script

Path:
`/Users/shalmalisohoni/.openclaw/workspace/skills/milo-desktop-actions/scripts/milo_bridge.py`

### Commands

1. Read desktop context:

```bash
python3 /Users/shalmalisohoni/.openclaw/workspace/skills/milo-desktop-actions/scripts/milo_bridge.py get_context --json
```

2. Get selected text from frontmost app:

```bash
python3 /Users/shalmalisohoni/.openclaw/workspace/skills/milo-desktop-actions/scripts/milo_bridge.py get_selection --json
```

3. Replace selection with provided text:

```bash
printf '%s' "$NEW_TEXT" | python3 /Users/shalmalisohoni/.openclaw/workspace/skills/milo-desktop-actions/scripts/milo_bridge.py replace_selection --stdin --json
```

4. Insert text at cursor:

```bash
printf '%s' "$NEW_TEXT" | python3 /Users/shalmalisohoni/.openclaw/workspace/skills/milo-desktop-actions/scripts/milo_bridge.py insert_text --stdin --json
```

## Required Interaction Pattern

For rewrite requests:
1. Run `get_selection`.
2. If selection is empty: ask user to select text and retry.
3. Generate rewrite preview in chat.
4. Ask: "Apply this rewrite?"
5. Only after "yes/apply/confirm", run `replace_selection`.

## Safety Rules

1. Do not auto-send messages/emails.
2. Do not apply destructive changes without explicit approval.
3. If bridge command errors, show a short error + next step.
4. Keep clipboard side effects minimal (bridge restores previous text clipboard best effort).

## Notes

- Requires macOS Accessibility permissions for keystrokes.
- Works best in standard text fields/editors that support Cmd+C/Cmd+V.

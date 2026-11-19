#!/bin/sh
# Supernomial plugin hook. Runs on this computer and sends nothing anywhere.
#   start  : session start. After any compaction, the after-compact note; otherwise the session start note.
#   prompt : each message. Local time and how full the chat is, and whether it has passed the handover line.
#   tool   : after each tool. The first time the chat passes the handover line, tell the agent once.
# prompt and tool speak only where Supernomial's agent works in this chat (its instructions were fetched, read from the
# transcript); elsewhere, and in cloud chats whose transcript is not on this machine, they stay silent.
LIMIT=60
WINDOW=1000000
DIR="${CLAUDE_PLUGIN_ROOT}/hooks"
IN=$(cat)
field() { printf '%s' "$IN" | tr ',{}' '\n\n\n' | sed -n "s/^ *\"$1\" *: *\"\([^\"]*\)\".*/\1/p" | head -n 1; }
TP=$(field transcript_path); SID=$(field session_id); SRC=$(field source)
MARK="${TMPDIR:-/tmp}/supernomial-handover-${SID:-none}"
ours() { [ -n "$TP" ] && [ -f "$TP" ] && grep -q 'get_instructions' "$TP"; }
num() { v=$(printf '%s' "$U" | sed -n "s/.*\"$1\":\([0-9]*\).*/\1/p"); echo "${v:-0}"; }
pct() {
  U=$(tail -n 400 "$TP" | grep -o '"usage":{[^}]*}' | tail -n 1)
  [ -n "$U" ] || return 1
  echo $(( ( $(num input_tokens) + $(num cache_creation_input_tokens) + $(num cache_read_input_tokens) ) * 100 / WINDOW ))
}
case "$1" in
  start)
    # every compaction gets the note, ours or not: in a cloud chat the transcript is not on this machine (19 Nov),
    # so the note itself says it applies only where our agent was working
    if [ "$SRC" = "compact" ]; then cat "$DIR/after-compact.md"; else cat "$DIR/session-start.md"; fi ;;
  prompt)
    ours || exit 0
    P=$(pct) || P=""
    # no hold: Cowork holds a message silently, whatever the reason says (tested 5 Nov); the brief makes the agent say it
    printf 'Supernomial: local time %s.' "$(date '+%Y-%m-%d %H:%M %Z')"
    [ -n "$P" ] && printf ' This chat is %s%% full.' "$P"
    if [ -n "$P" ] && [ "$P" -ge "$LIMIT" ]; then : > "$MARK"; printf ' It has passed the handover line (%s%%).' "$LIMIT"; fi
    printf '\n' ;;
  tool)
    ours || exit 0
    [ -f "$MARK" ] && exit 0
    P=$(pct) || exit 0
    if [ "$P" -ge "$LIMIT" ]; then
      : > "$MARK"
      printf 'Supernomial: this chat is %s%% full and has passed the handover line (%s%%).\n' "$P" "$LIMIT" >&2
      exit 2
    fi ;;
esac
exit 0

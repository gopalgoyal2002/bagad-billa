# Source from an interactive zsh. No command text, arguments or output are written.
[[ -o interactive ]] || return 0
[[ ${_BAGAD_BILLA_LOADED:-0} == 1 ]] && return 0
typeset -g _BAGAD_BILLA_LOADED=1
zmodload zsh/datetime
autoload -Uz add-zsh-hook
typeset -g _bb_started=0 _bb_active=0 _bb_git=0
_bb_emit() {
  local kind="$1" code="${2:-0}" elapsed="${3:-0}"
  local dir="$HOME/Library/Application Support/BagadBilli/events"
  local app=unknown
  case "${TERM_PROGRAM:-}" in
    Apple_Terminal) app=terminal ;;
    iTerm.app) app=iterm ;;
    vscode) app=vscode ;;
    *) [[ -n ${TERMINAL_EMULATOR:-} ]] && app=jetbrains ;;
  esac
  local ttyname="${TTY:t}"
  [[ "$ttyname" == ttys[0-9]* ]] || ttyname=terminal
  (umask 077
   mkdir -p "$dir" || exit
   local file="$dir/$$.json" temp="$dir/$$.tmp"
   printf '{"kind":"%s","code":%d,"duration":%d,"time":%d,"session":"%s","app":"%s"}\n' "$kind" "$code" "$elapsed" "$EPOCHSECONDS" "$ttyname" "$app" > "$temp" && mv -f "$temp" "$file"
  ) 2>/dev/null
  return 0
}
# Only the leading words are checked, inside the shell, to classify git milestones; the command itself is never written.
_bb_preexec() {
  _bb_started=$EPOCHSECONDS; _bb_active=1; _bb_git=0
  local cmd="${1#"${1%%[![:space:]]*}"}"
  case "$cmd" in "git push"*|"git commit"*|"git merge"*) _bb_git=1 ;; esac
}
_bb_precmd() {
  local result=$?
  if (( _bb_active )); then
    local elapsed=$(( EPOCHSECONDS - _bb_started ))
    if (( result == 0 && _bb_git )); then _bb_emit milestone 0 "$elapsed"
    elif (( result != 0 || elapsed >= 3 )); then
      if (( result == 0 )); then _bb_emit success 0 "$elapsed"
      else _bb_emit failure "$result" "$elapsed"; fi
    fi
  fi
  _bb_active=0
  return "$result"
}
# Call before a command that needs a decision, or from an integrated tool.
bagad-help() { _bb_emit attention 0 0; }
add-zsh-hook preexec _bb_preexec
add-zsh-hook precmd _bb_precmd

#!/bin/bash

set -euo pipefail

LABEL="com.codex.senplayer-airplay-auto-sync"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE="$SCRIPT_DIR/SenPlayerAudioAutomation.swift"
SHORTCUT_ASSET="$SCRIPT_DIR/../assets/SenPlayer-Auto-Sync.shortcut"
SHORTCUT_NAME="SenPlayer · 自动同步"
USER_HOME="${HOME:?HOME is not set}"
USER_ID="$(id -u)"
INSTALL_DIR="$USER_HOME/Library/Application Support/SenPlayerAirPlayAutoSync"
INSTALL_BINARY="$INSTALL_DIR/SenPlayerAudioAutomation"
LAUNCH_AGENTS_DIR="$USER_HOME/Library/LaunchAgents"
PLIST="$LAUNCH_AGENTS_DIR/$LABEL.plist"
LOG_DIR="$USER_HOME/Library/Logs"
LOG_FILE="$LOG_DIR/SenPlayerAirPlayAutoSync.log"
ERROR_LOG_FILE="$LOG_DIR/SenPlayerAirPlayAutoSync.error.log"
PREFERENCE_DOMAIN="$USER_HOME/Library/Containers/com.wuziqi.SenPlayer/Data/Library/Preferences/com.wuziqi.SenPlayer"
DEFAULT_AIRPLAY_DELAY="-2.0"

usage() {
  printf '%s\n' \
    'Usage: manage.sh <command> [options]' \
    '' \
    'Commands:' \
    '  probe                         Read-only checks and audio-device listing' \
    '  install [options]            Compile, install, and start the watcher' \
    '    --airplay-delay N          Set AirPlay compensation (default: -2.0)' \
    '    --with-shortcut            Open the optional Shortcut import screen' \
    '  install-shortcut             Open the optional Shortcut import screen' \
    '  status                        Show installation, service, delay, and devices' \
    '  once                          Apply the installed rule once' \
    '  logs                          Show recent watcher logs' \
    '  uninstall --yes               Remove files installed by this skill' \
    '  help                          Show this help'
}

require_macos() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    printf 'Error: this automation supports macOS only.\n' >&2
    exit 69
  fi
}

require_swiftc() {
  if ! /usr/bin/xcrun --find swiftc >/dev/null 2>&1; then
    printf 'Error: Swift compiler not found. Install Apple Command Line Tools first.\n' >&2
    exit 69
  fi
}

validate_delay() {
  local value="$1"
  if [[ ! "$value" =~ ^-?([0-9]+([.][0-9]*)?|[.][0-9]+)$ ]]; then
    printf 'Error: invalid delay value: %s\n' "$value" >&2
    exit 64
  fi
}

make_temp_dir() {
  mktemp -d "${TMPDIR:-/tmp}/senplayer-airplay-auto-sync.XXXXXX"
}

compile_binary() {
  local output="$1"
  local module_cache="$2"
  mkdir -p "$module_cache"
  /usr/bin/xcrun swiftc -O -module-cache-path "$module_cache" "$SOURCE" -o "$output"
  /usr/bin/codesign --force --sign - "$output" >/dev/null
}

print_preference() {
  local value
  if value="$(/usr/bin/defaults read "$PREFERENCE_DOMAIN" kGlobalAudioDelay 2>/dev/null)"; then
    printf 'SenPlayer delay: %s seconds\n' "$value"
  else
    printf 'SenPlayer delay: not set or preference container unavailable\n'
  fi
}

probe() {
  require_macos
  require_swiftc
  printf 'macOS: %s\n' "$(/usr/bin/sw_vers -productVersion)"
  printf 'Architecture: %s\n' "$(uname -m)"
  printf 'User: %s (uid %s)\n' "$(id -un)" "$USER_ID"
  printf 'SenPlayer container: '
  if [[ -d "$USER_HOME/Library/Containers/com.wuziqi.SenPlayer" ]]; then
    printf 'found\n'
  else
    printf 'not found; install and open SenPlayer once before enabling automation\n'
  fi
  print_preference

  local temp_dir
  temp_dir="$(make_temp_dir)"
  trap 'rm -rf "$temp_dir"' RETURN
  compile_binary "$temp_dir/SenPlayerAudioAutomation" "$temp_dir/module-cache"
  printf 'Audio devices:\n'
  "$temp_dir/SenPlayerAudioAutomation" --list
  trap - RETURN
  rm -rf "$temp_dir"
}

create_plist() {
  local output="$1"
  local delay="$2"

  rm -f "$output"
  /usr/bin/plutil -create xml1 "$output"
  /usr/bin/plutil -insert Label -string "$LABEL" "$output"
  /usr/bin/plutil -insert ProgramArguments -array "$output"
  /usr/bin/plutil -insert ProgramArguments.0 -string "$INSTALL_BINARY" "$output"
  /usr/bin/plutil -insert ProgramArguments.1 -string '--airplay-delay' "$output"
  /usr/bin/plutil -insert ProgramArguments.2 -string "$delay" "$output"
  /usr/bin/plutil -insert RunAtLoad -bool true "$output"
  /usr/bin/plutil -insert KeepAlive -bool true "$output"
  /usr/bin/plutil -insert ProcessType -string Interactive "$output"
  /usr/bin/plutil -insert LimitLoadToSessionType -string Aqua "$output"
  /usr/bin/plutil -insert ThrottleInterval -integer 5 "$output"
  /usr/bin/plutil -insert StandardOutPath -string "$LOG_FILE" "$output"
  /usr/bin/plutil -insert StandardErrorPath -string "$ERROR_LOG_FILE" "$output"
  /usr/bin/plutil -insert EnvironmentVariables -xml '<dict/>' "$output"
  /usr/bin/plutil -insert EnvironmentVariables.PATH -string '/usr/bin:/bin:/usr/sbin:/sbin' "$output"
  /usr/bin/plutil -lint "$output" >/dev/null
}

install_watcher() {
  require_macos
  require_swiftc

  local delay="$DEFAULT_AIRPLAY_DELAY"
  local with_shortcut=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --airplay-delay)
        if [[ $# -lt 2 ]]; then
          printf 'Error: --airplay-delay requires a numeric value.\n' >&2
          exit 64
        fi
        delay="$2"
        shift 2
        ;;
      --with-shortcut)
        with_shortcut=true
        shift
        ;;
      *)
        printf 'Error: unknown install option: %s\n' "$1" >&2
        exit 64
        ;;
    esac
  done
  validate_delay "$delay"

  if [[ ! -d "$USER_HOME/Library/Containers/com.wuziqi.SenPlayer" ]]; then
    printf 'Error: SenPlayer preference container was not found. Open SenPlayer once, then retry.\n' >&2
    exit 69
  fi

  local temp_dir
  temp_dir="$(make_temp_dir)"
  trap 'rm -rf "$temp_dir"' RETURN
  printf 'Compiling the native watcher for this Mac...\n'
  compile_binary "$temp_dir/SenPlayerAudioAutomation" "$temp_dir/module-cache"
  create_plist "$temp_dir/$LABEL.plist" "$delay"

  mkdir -p "$INSTALL_DIR" "$LAUNCH_AGENTS_DIR" "$LOG_DIR"
  /bin/launchctl bootout "gui/$USER_ID" "$PLIST" >/dev/null 2>&1 || true

  /usr/bin/install -m 755 "$temp_dir/SenPlayerAudioAutomation" "$INSTALL_BINARY.new"
  /bin/mv -f "$INSTALL_BINARY.new" "$INSTALL_BINARY"
  /usr/bin/install -m 644 "$temp_dir/$LABEL.plist" "$PLIST.new"
  /bin/mv -f "$PLIST.new" "$PLIST"

  /bin/launchctl bootstrap "gui/$USER_ID" "$PLIST"
  /bin/launchctl enable "gui/$USER_ID/$LABEL"
  /bin/launchctl kickstart -k "gui/$USER_ID/$LABEL"
  /bin/sleep 1

  if ! /bin/launchctl print "gui/$USER_ID/$LABEL" >/dev/null 2>&1; then
    printf 'Error: LaunchAgent did not start. Check %s and %s\n' "$LOG_FILE" "$ERROR_LOG_FILE" >&2
    exit 70
  fi

  printf 'Installed and started %s\n' "$LABEL"
  printf 'AirPlay delay: %s seconds; local delay: 0.0 seconds\n' "$delay"
  printf 'Log: %s\n' "$LOG_FILE"
  trap - RETURN
  rm -rf "$temp_dir"

  if [[ "$with_shortcut" == true ]]; then
    install_shortcut
  fi
}

install_shortcut() {
  require_macos
  if [[ ! -f "$SHORTCUT_ASSET" ]]; then
    printf 'Error: bundled Shortcut asset is missing: %s\n' "$SHORTCUT_ASSET" >&2
    exit 66
  fi

  local shortcut_list
  if shortcut_list="$(/usr/bin/shortcuts list 2>/dev/null)" \
      && printf '%s\n' "$shortcut_list" | /usr/bin/grep -Fqx "$SHORTCUT_NAME"; then
    printf 'Shortcut is already installed: %s\n' "$SHORTCUT_NAME"
    return
  fi

  /usr/bin/open "$SHORTCUT_ASSET"
  printf 'Opened the Shortcut import screen for: %s\n' "$SHORTCUT_NAME"
  printf 'Review it in Shortcuts, then choose Add Shortcut to finish.\n'
}

configured_delay() {
  if [[ -f "$PLIST" ]]; then
    /usr/bin/plutil -extract ProgramArguments.2 raw "$PLIST" 2>/dev/null || printf 'unknown'
  else
    printf 'not installed'
  fi
}

service_status() {
  if /bin/launchctl print "gui/$USER_ID/$LABEL" >/dev/null 2>&1; then
    printf 'LaunchAgent: loaded\n'
    /bin/launchctl print "gui/$USER_ID/$LABEL" 2>/dev/null | /usr/bin/awk '/state =|pid =|last exit code =/ { sub(/^[[:space:]]+/, ""); print "  " $0 }'
  else
    printf 'LaunchAgent: not loaded\n'
  fi
}

shortcut_status() {
  local shortcut_list
  if shortcut_list="$(/usr/bin/shortcuts list 2>/dev/null)"; then
    if printf '%s\n' "$shortcut_list" | /usr/bin/grep -Fqx "$SHORTCUT_NAME"; then
      printf 'Optional Shortcut: installed (%s)\n' "$SHORTCUT_NAME"
    else
      printf 'Optional Shortcut: not installed\n'
    fi
  else
    printf 'Optional Shortcut: status unavailable in this session\n'
  fi
}

status() {
  require_macos
  printf 'Binary: %s\n' "$([[ -x "$INSTALL_BINARY" ]] && printf installed || printf missing)"
  printf 'LaunchAgent plist: %s\n' "$([[ -f "$PLIST" ]] && printf installed || printf missing)"
  printf 'Configured AirPlay delay: %s seconds\n' "$(configured_delay)"
  print_preference
  service_status
  shortcut_status

  if [[ -x "$INSTALL_BINARY" ]]; then
    printf 'Audio devices:\n'
    "$INSTALL_BINARY" --list
  else
    printf 'Audio devices: unavailable until installed; run probe for a temporary check\n'
  fi

  printf 'Recent log:\n'
  if [[ -f "$LOG_FILE" ]]; then
    /usr/bin/tail -n 12 "$LOG_FILE"
  else
    printf '  no log yet\n'
  fi
  if [[ -s "$ERROR_LOG_FILE" ]]; then
    printf 'Recent error log:\n'
    /usr/bin/tail -n 12 "$ERROR_LOG_FILE"
  fi
}

apply_once() {
  require_macos
  if [[ ! -x "$INSTALL_BINARY" || ! -f "$PLIST" ]]; then
    printf 'Error: automation is not installed.\n' >&2
    exit 69
  fi
  local delay
  delay="$(configured_delay)"
  "$INSTALL_BINARY" --airplay-delay "$delay" --once
}

show_logs() {
  printf 'Watcher log (%s):\n' "$LOG_FILE"
  if [[ -f "$LOG_FILE" ]]; then
    /usr/bin/tail -n 40 "$LOG_FILE"
  else
    printf '  no log yet\n'
  fi
  printf 'Error log (%s):\n' "$ERROR_LOG_FILE"
  if [[ -f "$ERROR_LOG_FILE" ]]; then
    /usr/bin/tail -n 40 "$ERROR_LOG_FILE"
  else
    printf '  no error log yet\n'
  fi
}

uninstall_watcher() {
  require_macos
  if [[ "${1:-}" != '--yes' ]]; then
    printf 'Refusing to uninstall without explicit confirmation. Re-run: manage.sh uninstall --yes\n' >&2
    exit 64
  fi

  /bin/launchctl bootout "gui/$USER_ID" "$PLIST" >/dev/null 2>&1 || true
  /bin/rm -f "$PLIST"
  /bin/rm -rf "$INSTALL_DIR"
  printf 'Removed the LaunchAgent and installed watcher.\n'
  printf 'Preserved SenPlayer preferences, Shortcuts, and logs.\n'
}

command="${1:-help}"
if [[ $# -gt 0 ]]; then
  shift
fi

case "$command" in
  probe)
    probe "$@"
    ;;
  install)
    install_watcher "$@"
    ;;
  install-shortcut)
    install_shortcut "$@"
    ;;
  status)
    status "$@"
    ;;
  once)
    apply_once "$@"
    ;;
  logs)
    show_logs "$@"
    ;;
  uninstall)
    uninstall_watcher "$@"
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    printf 'Error: unknown command: %s\n' "$command" >&2
    usage >&2
    exit 64
    ;;
esac

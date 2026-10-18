#!/bin/bash
# Real packet dropouts: continuous until Stop, or an optional timed run. No global PF reload, state flush, or firewall disable.
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
ANCHOR=com.apple/000.zoom-lag-lab
STATE=/var/run/zoom-lag-lab
PF=/sbin/pfctl
fail() { echo "ERROR: $*" >&2; exit 1; }
profile=${2:-choppy}
case "$profile" in
  choppy) blocked=1; clear=2; duration=30;;
  severe) blocked=3; clear=1; duration=30;;
  blackout) blocked=5; clear=0; duration=5;;
  *) fail 'Profile must be choppy, severe, or blackout.';;
esac
mode=${4:-continuous}
owner=${5:-0}
[[ $mode == continuous || $mode == timed ]] || fail 'Mode must be continuous or timed.'
[[ $owner =~ ^[0-9]+$ ]] || fail 'Invalid supervising process.'
if [[ $mode == continuous ]]; then duration=0; fi
action=${1:-help}
if [[ $action == status ]]; then
  if [[ -f $STATE/status ]]; then cat "$STATE/status"; else printf 'idle\n0\n\n\n'; fi
  exit 0
fi
if [[ $action == help ]]; then
  echo 'Usage: sudo bash lag.sh start [choppy|severe|blackout] [en0] [continuous|timed]'
  echo '       sudo bash lag.sh stop'
  echo '       bash lag.sh preview [choppy|severe|blackout] [en0]'
  exit 0
fi
iface=${3:-}
if [[ $action == start || $action == preview ]]; then
  iface=${iface:-$(/sbin/route -n get default 2>/dev/null | awk '/interface:/{print $2; exit}' || true)}
fi
if [[ $action == preview ]]; then
  [[ $iface =~ ^en[0-9]+$ ]] || fail 'Supply a physical interface such as en0.'
  length="${duration} seconds"
  [[ $mode != continuous ]] || length="until Restore or Control-C"
  echo "Profile: $profile; run length: $length; ${blocked}s dropping / ${clear}s recovery."
  echo "block drop quick on $iface all"
  exit 0
fi
[[ $EUID == 0 ]] || fail 'Administrator access is required.'
publish_status() {
  printf '%s\n%s\n%s\n%s\n%s\n' "$1" "$2" "$iface" "$profile" "${3:-}" > "$STATE/status.tmp"
  chmod 644 "$STATE/status.tmp"
  mv -f "$STATE/status.tmp" "$STATE/status"
}
cleanup() {
  local failed=0 token=''
  [[ -d $STATE && ! -L $STATE ]] || return 0
  publish_status restoring 0
  if [[ -f $STATE/rules-owned ]]; then
    if $PF -a "$ANCHOR" -f /dev/null; then
      rm -f "$STATE/rules-owned"
    else
      publish_status error 0
      echo 'Could not remove packet-drop rules. Recovery record retained; try Restore again.' >&2
      return 1
    fi
  fi
  if [[ -f $STATE/token ]]; then
    token=$(cat "$STATE/token")
    if [[ $token =~ ^[0-9]+$ ]]; then
      if $PF -X "$token"; then rm -f "$STATE/token"; else failed=1; fi
    else
      failed=1
    fi
  fi
  if [[ $failed == 0 ]]; then
    rm -rf "$STATE"
    echo 'Restored: test rules removed and its PF reference released.'
  else
    publish_status error 0
    echo 'Restore incomplete. Retry Restore connection. A Mac restart clears temporary rules.' >&2
    return 1
  fi
}
if [[ $action == stop ]]; then
  if [[ -d $STATE ]]; then
    touch "$STATE/stop"
    owner=$(cat "$STATE/pid" 2>/dev/null || true)
    if [[ $owner =~ ^[0-9]+$ ]] && kill -0 "$owner" 2>/dev/null; then
      for attempt in 1 2 3 4 5 6; do
        [[ -d $STATE ]] || exit 0
        sleep 1
      done
      fail 'Test process is still restoring. Wait a moment and try Restore again.'
    else
      cleanup
    fi
  else
    echo 'No saved Zoom Lag Lab session.'
  fi
  exit 0
fi
[[ $action == start ]] || fail 'Unknown action; use help.'
[[ $iface =~ ^en[0-9]+$ ]] || fail 'Choose a physical Wi-Fi or Ethernet connection. Disconnect VPNs first.'
/sbin/ifconfig "$iface" >/dev/null
[[ $(/usr/sbin/sysctl -n net.inet.ip.forwarding) == 0 ]] || fail 'Turn off Internet Sharing / IPv4 forwarding first.'
[[ $(/usr/sbin/sysctl -n net.inet6.ip6.forwarding) == 0 ]] || fail 'Turn off Internet Sharing / IPv6 forwarding first.'
if [[ $owner != 0 ]]; then kill -0 "$owner" 2>/dev/null || fail 'The controlling app is no longer running.'; fi
[[ ! -e $STATE ]] || fail 'An active session or recovery record exists. Use Restore connection first.'
info=$($PF -s info 2>/dev/null)
printf '%s\n' "$info" | grep -q '^Status: Disabled' || fail 'Another component has PF enabled. This test cannot safely guarantee dropouts alongside it; no changes made.'
entries=$(printf '%s\n' "$info" | awk '/current entries/{print $3}')
[[ $entries == 0 ]] || fail 'Existing PF connection states could bypass the test. No changes made.'
$PF -s rules 2>/dev/null | grep -Fq 'anchor "com.apple/*"' || fail 'Required live Apple filter anchor is missing; no changes made.'
existing=$($PF -a "$ANCHOR" -s rules 2>/dev/null)
[[ -z $existing ]] || fail 'Test anchor already contains rules. No changes made.'
umask 077
mkdir "$STATE"
chmod 755 "$STATE"
printf '%s\n' "$$" > "$STATE/pid"
trap cleanup EXIT
trap 'exit 130' INT TERM HUP
publish_status preparing 0
printf 'block drop quick on %s all\n' "$iface" > "$STATE/rules"
$PF -n -a "$ANCHOR" -f "$STATE/rules"
enabled=$($PF -E 2>&1)
token=$(printf '%s\n' "$enabled" | awk '/Token :/{print $3}')
[[ $token =~ ^[0-9]+$ ]] || fail "PF returned no reference token: $enabled"
printf '%s\n' "$token" > "$STATE/token"
touch "$STATE/rules-owned"
$PF -a "$ANCHOR" -f "$STATE/rules"
deadline=0
if (( duration > 0 )); then deadline=$(( $(date +%s) + duration )); fi
publish_status active "$deadline" dropping
echo "ACTIVE on $iface: $profile; ${blocked}s dropping / ${clear}s recovery; mode=$mode. Use Restore or Control-C to stop."
SECONDS=0
phase=1
while (( duration == 0 || SECONDS < duration )); do
  if [[ $owner != 0 ]] && ! kill -0 "$owner" 2>/dev/null; then
    echo 'Controlling app exited; restoring connection.'
    break
  fi
  [[ ! -f $STATE/stop ]] || break
  desired=0
  if (( SECONDS % (blocked + clear) < blocked )); then desired=1; fi
  if [[ $desired != "$phase" ]]; then
    if [[ $desired == 1 ]]; then
      # Existing states can skip new filter rules. Fail rather than give a false active result.
      entries=$($PF -s info 2>/dev/null | awk '/current entries/{print $3}')
      [[ $entries == 0 ]] || fail 'Another component created PF connection states. Stopping to avoid an unreliable test.'
      $PF -a "$ANCHOR" -f "$STATE/rules"
      publish_status active "$deadline" dropping
    else
      $PF -a "$ANCHOR" -f /dev/null
      publish_status active "$deadline" recovery
    fi
    phase=$desired
  fi
  sleep 0.1
done

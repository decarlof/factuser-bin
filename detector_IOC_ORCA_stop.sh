#!/bin/bash
#
# Stop the ORCA detector IOC (run_ioc.py) on factdetector.
#
# The Vieworks IOC has a synApps .pl launcher with a "stop" subcommand.
# This one does not -- it is a python program the operator stops with ^C
# in its terminal.  So this sends SIGINT, exactly what ^C sends, giving
# run_ioc.py the same chance to close the camera and drop its CA server
# cleanly.  SIGKILL is deliberately never sent: if SIGINT is not enough,
# something is wrong and forcing it would skip the camera shutdown.
#
# Finding the right process is the dangerous part.
#
# "pgrep -f run_ioc.py" also matches this script's own ssh command line,
# so a naive version kills the wrong thing.  An earlier draft embedded
# an awk filter with nested '"'"' quoting; the quoting collapsed, the
# pattern matched every line of ps, and a dry run showed it would have
# signalled pid 1.  Hence the rules below:
#
#   * the match pattern is bracketed -- run_io[c] -- so a literal copy
#     of the pattern, as it appears in this script's own command line,
#     does not match the pattern itself;
#   * every candidate pid is then confirmed against /proc/<pid>/comm,
#     which must be python, something no shell or ssh wrapper is;
#   * pids below 300 are refused outright as a backstop.
#
# No nested quoting: the remote body is a here-doc fed to "ssh bash -s",
# so it is passed literally and never re-parsed by an intermediate
# shell.

set -u

TAB_NAME="19-BM ORCA Detector IOC stop"
REMOTE_USER="factuser"
REMOTE_HOST="factdetector"

read -r -d '' BODY <<'REMOTE_EOF'
set -u

# Bracketed so this pattern cannot match a literal copy of itself.
pids=$(pgrep -f "run_io[c]\.py" || true)

confirmed=""
for pid in $pids; do
    [ "$pid" -lt 300 ] 2>/dev/null && continue          # backstop
    comm=$(cat "/proc/$pid/comm" 2>/dev/null) || continue
    case "$comm" in python*) ;; *) continue ;; esac     # must be python
    grep -qa -- "ORCA:" "/proc/$pid/cmdline" 2>/dev/null || continue
    confirmed="$confirmed $pid"
done

if [ -z "$confirmed" ]; then
    echo "ORCA IOC (run_ioc.py --prefix ORCA:) is not running."
    exit 0
fi

echo "Matched:"
for pid in $confirmed; do
    echo "  pid $pid  $(tr '\0' ' ' < /proc/$pid/cmdline)"
done

echo "Sending SIGINT (same as ^C)..."
for pid in $confirmed; do kill -INT "$pid"; done

for _ in 1 2 3 4 5 6 7 8 9 10; do
    sleep 1
    alive=""
    for pid in $confirmed; do
        [ -d "/proc/$pid" ] && alive="$alive $pid"
    done
    [ -z "$alive" ] && { echo "Stopped."; exit 0; }
done

echo "Still running after 10 s:$alive"
echo "Left alone deliberately -- SIGKILL would skip the camera shutdown."
echo "Attach to its terminal and press ^C, or investigate before forcing."
exit 1
REMOTE_EOF

run_it() {
    if [ "$(hostname -s)" = "$REMOTE_HOST" ]; then
        printf '%s\n' "$BODY" | bash -s
    else
        printf '%s\n' "$BODY" | ssh -o BatchMode=yes "${REMOTE_USER}@${REMOTE_HOST}" bash -s
    fi
}

export -f run_it 2>/dev/null || true
export BODY REMOTE_HOST REMOTE_USER

# See detector_ORCA.sh for why the D-Bus ping and the xterm fallback:
# gnome-terminal renders on its own display rather than $DISPLAY, so
# under X11 forwarding its window opens where nobody is looking.
if gdbus call --session --dest org.gnome.Terminal \
        --object-path /org/gnome/Terminal/Factory0 \
        --method org.freedesktop.DBus.Peer.Ping >/dev/null 2>&1; then
    gnome-terminal --tab --title="$TAB_NAME" -- bash -c 'run_it; echo; read -rp "press enter to close "'
else
    xterm -hold -title "$TAB_NAME" -e bash -c 'run_it' &
fi

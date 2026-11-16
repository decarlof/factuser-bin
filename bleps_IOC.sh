#!/bin/bash
#
# Start the 19-BM BLEPS IOC.
#
# The IOC runs on hounsfield, not on the tomography hosts, and its
# directory belongs to the controls group (tfanning / aesbc) rather than
# to factuser.  It publishes every 19bm:BLEPS: PV.  It does NOT start at
# boot -- there is no systemd unit and no @reboot entry -- so after any
# hounsfield reboot the PVs are simply gone until somebody runs this.
#
# Equipment protection is unaffected while it is down: the interlocks run
# in the Allen-Bradley PLC at 10.54.129.19, independently of EPICS.  A
# dead IOC means blind monitoring, not unprotected equipment.
#
# Deliberately a command and not a screen button.  The 19-BM docs
# (internal/19bm/bleps.rst) say plainly:
#
#     This IOC serves equipment protection for the whole beamline and
#     runs on a different host from the tomography IOCs, under the
#     controls group's account.  Do not wire start / stop buttons for
#     it into an instrument screen.
#
# so do not add this to mct_main.adl or bleps_status.adl.  2-BM's
# bleps_IOC.sh *is* wired into its BLEPS screen; that is the pattern the
# warning is about, and the 2-BM script still points at arcturus and the
# 2bmb account.
#
# Differences from the 2-BM version this was modelled on:
#
#   * "start", not "run".  run keeps the IOC in the foreground of the
#     terminal it was launched from, so it dies when that window closes.
#     start detaches it into a screen session named 19bmBLEPS, which is
#     what the docs describe and what survives a logout.
#
#   * No terminal emulator.  2-BM wraps the ssh in gnome-terminal, which
#     renders through gnome-terminal-server over D-Bus on *its own*
#     display rather than $DISPLAY -- over X11 forwarding the window
#     opens where nobody is looking and the script still exits 0.  Since
#     start detaches anyway, no terminal is needed at all.

set -u

HOST=hounsfield
IOC=19bmBLEPS
SOFTIOC=/net/s19dserv/xorApps/epics/synApps_6_3/ioc/19bmBLEPS/iocBoot/ioc19bmBLEPS/softioc

case "${1:-start}" in
    start|stop|status|console) ACTION="$1" ;;
    *)  echo "usage: $(basename "$0") [start|stop|status|console]" >&2
        echo "  console attaches to the running IOC shell; detach with ^a d," >&2
        echo "  never ^c -- that stops the IOC." >&2
        exit 2 ;;
esac

if [ "$ACTION" = "console" ]; then
    # console needs an interactive terminal, so hand the tty over.
    exec ssh -t "$HOST" "cd '$SOFTIOC' && ./${IOC}.pl console"
fi

ssh -o BatchMode=yes "$HOST" "cd '$SOFTIOC' && ./${IOC}.pl $ACTION" 2>&1 | sed 's/^/  /'

# Report what actually happened rather than trusting the exit code: the
# launcher returns 0 for "already running", and a PV read is the only
# check that proves Channel Access clients can see it.
if [ "$ACTION" = "start" ]; then
    sleep 3
    CAGET=/APSshare/epics/base-7.0.4.1/bin/linux-x86_64/caget
    if [ -x "$CAGET" ] && "$CAGET" -t -w 5 19bm:BLEPS:FaultExists >/dev/null 2>&1; then
        echo "  19bm:BLEPS: PVs are answering."
    else
        echo "  WARNING: 19bm:BLEPS: PVs are not answering yet."
        echo "  Give it a few seconds and retry, then: $(basename "$0") status"
        echo "  From a public-network host you also need the sector gateway"
        echo "  s19pvgate (164.54.129.12) in EPICS_CA_ADDR_LIST."
    fi
fi

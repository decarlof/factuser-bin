#!/bin/bash
#
# Start / stop the 19-BM hexapod IOC (19bmHXP).
#
# Serves 19bmHXP:m1 .. m6 -- the six hexapod axes under the rotary:
#   m1 X, m2 Y, m3 Z, m4 AX, m5 AY, m6 AZ
# tomoscan binds SAMPLE_X to m1 and SAMPLE_Y to m2, so a mosaic scan
# cannot move between tiles while this IOC is down.
#
# Runs on hounsfield, not on the tomography hosts.  Like the other
# hounsfield IOCs it does NOT start at boot -- no systemd unit, no
# @reboot entry -- so after a reboot the PVs are simply gone until
# somebody runs this.
#
# Replaces the three buttons on iocs_start.adl that pointed at
# /home/beams/2BMB/bin/hexapod_IOC*.sh.  Those were left over from the
# 2-BM screen this one was copied from: they reached into 2-BM's
# account, against 2-BM's hosts, and two of them were not even readable
# here (mode rwx--x--x, owner 2bmb).  The REBOOT button went with them;
# it ran hexapod_reboot.py, which power-cycles the hexapod *controller*
# and is a different operation from starting this IOC.  If controller
# power-cycling is wanted later it needs its own 19-BM script.
#
# A note on ownership.  The IOC directory belongs to nmarks / aesbc, the
# controls group, and bleps.rst warns against wiring start / stop
# buttons for controls-group IOCs into an instrument screen.  That
# warning is written about BLEPS, whose argument is that it serves
# equipment protection for the whole beamline; the hexapod is an
# instrument stage and carries no interlock role, so the reasoning does
# not transfer.  Wiring this one was an explicit decision.
#
# Modelled on bleps_IOC.sh, and for the same reasons:
#   * "start", not "run" -- run holds the IOC in the foreground of the
#     launching terminal and it dies when that window closes; start
#     detaches it into a screen session named 19bmHXP.
#   * no gnome-terminal -- it renders through gnome-terminal-server over
#     D-Bus on its own display rather than $DISPLAY, so under X11
#     forwarding the window opens where nobody is looking and the script
#     still exits 0.  That is why the tomoscan IOC appeared not to start
#     on 2026-11-09 when in fact it had.

set -u

HOST=hounsfield
IOC=19bmHXP
SOFTIOC=/net/s19dserv/xorApps/epics/synApps_6_3/ioc/19bmHXP/iocBoot/ioc19bmHXP/softioc
CHECK_PV=19bmHXP:m2.RBV          # hexapod Y -- the axis mosaics step through

case "${1:-start}" in
    start|stop|status|console) ACTION="$1" ;;
    *)  echo "usage: $(basename "$0") [start|stop|status|console]" >&2
        echo "  console attaches to the running IOC shell; detach with ^a d," >&2
        echo "  never ^c -- that stops the IOC." >&2
        exit 2 ;;
esac

if [ "$ACTION" = "console" ]; then
    exec ssh -t "$HOST" "cd '$SOFTIOC' && ./${IOC}.pl console"
fi

ssh -o BatchMode=yes "$HOST" "cd '$SOFTIOC' && ./${IOC}.pl $ACTION" 2>&1 | sed 's/^/  /'

# Report what actually happened rather than trusting the exit code: the
# launcher returns 0 for "already running", and only a PV read proves
# that Channel Access clients can see it.
if [ "$ACTION" = "start" ]; then
    sleep 3
    CAGET=/APSshare/epics/base-7.0.4.1/bin/linux-x86_64/caget
    if [ -x "$CAGET" ] && "$CAGET" -t -w 5 "$CHECK_PV" >/dev/null 2>&1; then
        echo "  $CHECK_PV is answering."
    else
        echo "  WARNING: $CHECK_PV is not answering yet."
        echo "  Retry in a few seconds, then: $(basename "$0") status"
        echo "  If the IOC is running but PVs do not resolve, check caDirServ:"
        echo "      ssh hounsfield 'pgrep -a caDirServ'"
        echo "  It has no systemd unit and does not survive a reboot; without"
        echo "  it no private-subnet PV resolves from a public-network host."
    fi
fi

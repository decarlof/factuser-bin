#!/bin/bash
#
# Start the ORCA detector IOC (Hamamatsu ORCA-Fire) on factdetector.
#
# Serves the ORCA: PV prefix.  Unlike the Vieworks IOC, this is not a
# synApps softIoc with a .pl launcher -- it is a python program,
# run_ioc.py, from ~/Software/detector.  It runs in the FOREGROUND of
# the terminal this opens, and the operator stops it with ^C in that
# terminal, or with detector_IOC_ORCA_stop.sh.
#
# Host note: factdetector (10.54.129.15).  Not "fastdetector", which
# does not resolve.
#
# conda.sh is sourced explicitly rather than relying on "conda activate"
# being available.  That is a shell function defined by the init block
# in ~/.bashrc, and .bashrc is only read for an ssh remote command; when
# this script runs on factdetector itself it skips the ssh and the body
# executes in a plain non-interactive bash that never reads it.  Without
# the explicit source, conda activate fails with "Run 'conda init'
# before 'conda activate'" and the system python is used instead, where
# the detector package is not importable.  Same reasoning as
# tomoscan_server.sh.

set -u

TAB_NAME="19-BM ORCA Detector IOC"
REMOTE_USER="factuser"
REMOTE_HOST="factdetector"
WORK_DIR="/home/beams/FACTUSER/Software/detector"
CONDA_SH="/home/beams/FACTUSER/miniconda3/etc/profile.d/conda.sh"
CONDA_ENV="detector"
CAMERA="hamamatsu.orca_fire_dcam"
PREFIX="ORCA:"

# TomoScan softioc prefix.  run_ioc.py defaults this to "32id:TomoScan:",
# a 32-ID leftover that must be overridden here.  cam_plugin subscribes to
# <ts-prefix>HDF5Location and snapshots it per frame so the HDF5 writer can
# route frames to /exchange/data, /exchange/data_white and
# /exchange/data_dark.  Left at the default the subscription never connects
# -- 32id:TomoScan:HDF5Location does not exist on this network -- and the
# writer cannot tell projections from flats and darks.  The startup log
# prints the prefix it used; check that line reads 19bm:, not 32id:.
TS_PREFIX="19bm:TomoScan:"

# The instance running on 2026-11-16 was started with --gui.  Left out
# here because the documented start command does not include it; add it
# back on this line if the viewer is wanted.  There is no need to restart
# the IOC just to get the window back: run_ioc.py --gui-only --prefix ORCA:
# attaches a GUI to the already-running IOC.
#
# --gui is on.  The viewer window reaches the operator because the ssh to
# factdetector already has X11 forwarding enabled (DISPLAY arrives as
# localhost:NN.0), so no -X is needed on the ssh line below.
#
# To drop back to IOC-only, set EXTRA_ARGS="".  A terminal showing only
# log lines and no window is then the expected result -- the IOC is up and
# serving once the last line reads "Serving 107 PVs".
#
# To reopen the window after closing it, there is no need to restart the
# IOC:  python run_ioc.py --gui-only --prefix ORCA:
EXTRA_ARGS="--gui"

BODY="
        . ${CONDA_SH}
        conda activate ${CONDA_ENV}
        cd ${WORK_DIR}
        python run_ioc.py --camera ${CAMERA} --prefix ${PREFIX} --ts-prefix ${TS_PREFIX} ${EXTRA_ARGS}
"

if [ "$(hostname -s)" = "$REMOTE_HOST" ]; then
    CMD="$BODY"
else
    CMD="ssh -t ${REMOTE_USER}@${REMOTE_HOST} '$BODY'"
fi

# gnome-terminal renders through gnome-terminal-server over D-Bus, on
# *its own* display rather than $DISPLAY: under X11 forwarding the
# window opens where nobody is looking and this script still exits 0.
# Ping the factory first and fall back to xterm, which honours $DISPLAY
# directly.  Same guard as the Vieworks script.
if gdbus call --session --dest org.gnome.Terminal \
        --object-path /org/gnome/Terminal/Factory0 \
        --method org.freedesktop.DBus.Peer.Ping >/dev/null 2>&1; then
    gnome-terminal --tab --title="$TAB_NAME" -- bash -c "$CMD"
else
    xterm -hold -title "$TAB_NAME" -e bash -c "$CMD" &
fi

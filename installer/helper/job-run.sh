#!/bin/bash
# Helper job run: a job that brings its own script and files, for work that needs Linux's
# file systems on files the host has (the iOS 26 installer's Linux steps, Install-iOS26.ps1
# -Linux helper). The helper holds the tools; what to run comes with each job.
#
# Disks, by virtio serial:
#   in      a tar the host made (read-only), unpacked into /work: the job's files, and
#           .job/run   the script to run (a path in the tar), with /work as its directory
#           .job/disks lines "SERIAL PATH": the disk with that serial is linked at PATH
#                      (relative to /work, or absolute), so the script finds it where it
#                      would find the file
#           .job/out   the paths (relative to /work) to hand back, one per line; optional
#   out     an empty disk: the paths .job/out lists go onto it as a tar from its first byte,
#           and "ASOFT: out BYTES" says how long that tar is
#   others  the job's own disks (images, qcow2 disks: the host opens them), linked as
#           .job/disks says
# The script's output goes to the console as it is; its exit code is the job's.
set -uo pipefail

dev() {
    local d
    for d in /sys/block/vd*; do
        if [ "$(cat "$d/serial" 2>/dev/null)" = "$1" ]; then echo "/dev/${d##*/}"; return 0; fi
    done
    return 1
}

in=$(dev in) || { echo "ASOFT: no disk with serial in"; exit 2; }
mkdir -p /work
mount -t tmpfs -o size=75% work /work
tar -xf "$in" -C /work || { echo "ASOFT: cannot unpack the in disk"; exit 2; }
cd /work
run=$(cat .job/run 2>/dev/null)
[ -n "$run" ] && [ -f "$run" ] || { echo "ASOFT: no script to run (.job/run)"; exit 2; }
if [ -f .job/disks ]; then
    while read -r serial path; do
        [ -n "$serial" ] || continue
        d=$(dev "$serial") || { echo "ASOFT: no disk with serial $serial (for $path)"; exit 2; }
        mkdir -p "$(dirname "$path")"
        ln -sfn "$d" "$path"
        echo "ASOFT: disk $serial $d -> $path ($(( $(blockdev --getsize64 "$d") >> 20 )) MiB)"
    done < .job/disks
fi

bash "$run"
rc=$?
if [ $rc = 0 ] && [ -s .job/out ]; then
    out=$(dev out) || { echo "ASOFT: no disk with serial out"; exit 2; }
    while read -r p; do
        [ -z "$p" ] || [ -e "$p" ] || { echo "ASOFT: the job made no $p"; exit 3; }
    done < .job/out
    bytes=$(tar -cf - --dereference -T .job/out | tee "$out" | wc -c)
    sync
    echo "ASOFT: out $bytes"
fi
exit $rc

#!/bin/bash
# This script checks the status of the upstream Debian mirror.
# Specifically, it checks the status file in the project/trace/
# directory in the upstream mirror and in the local mirror,
# and checks the following conditions:
#
# - If the pull from upstream mirror is less than 2 hours old,
#   then the mirror is considered up-to-date, and no action is taken.
# - If the pull from upstream mirror is older than 2 hours old, and
#   the local mirror is older than the upstream mirror, then a new
#   pull is initiated.
# - If the pull from upstream mirror is older than 2 hours old, and
#   the local mirror is newer than the upstream mirror, then the
#   local mirror is considered up-to-date, and no action is taken.
#
# This script is intended to be run repeatedly by a cron job or
# a systemd timer.

LOCAL_MIRROR="lidsol.fi-b.unam.mx"
MIRROR_DIRECTORY=/srv/debian

# Set the upstream mirror URL
UPSTREAM_MIRROR=debian.csail.mit.edu
UPSTREAM_MIRROR_URL="https://${UPSTREAM_MIRROR}/debian/project/trace/${UPSTREAM_MIRROR}"

function get_upstream_time() {
    curl -s "${UPSTREAM_MIRROR_URL}" | head -n 1
}

function get_local_time() {
    if [ -f ${MIRROR_DIRECTORY}/project/trace/${LOCAL_MIRROR} ]; then
        cat ${MIRROR_DIRECTORY}/project/trace/${LOCAL_MIRROR} | head -n 1
    else
        echo "1970-01-01 00:00:00 UTC"
    fi
}

function should_pull() {
    local_mirror_time=$1
    upstream_time=$2
    current_time=$3
    # Log input of function to stderr
    local_mirror_time_epoch=$(date -d "$local_mirror_time" +%s)
    upstream_time_epoch=$(date -d "$upstream_time" +%s)
    current_time_epoch=$(date -d "$current_time" +%s)

    # If the local mirror is more than 4 hours old, then the mirror is considered out of date
    if [ $(($upstream_time_epoch - $local_mirror_time_epoch)) -gt 14400 ]; then
        echo "true"
        return
    fi

    # If it has been less than 2 hours since the upstream mirror started updating,
    # then the mirror is considered up-to-date
    if [ $upstream_time_epoch -gt $(($current_time_epoch - 7200)) ]; then
        # Log the operation above to stderr
        echo "false"
        return
    fi

    # If the local mirror is older than the upstream mirror, then the local mirror
    # is considered out of date
    if [ $local_mirror_time_epoch -lt $upstream_time_epoch ]; then
        echo "true"
    else
        echo "false"
    fi
}

# If this script is called with the --test flag, then it does not perform any actions
if [ "$1" == "--test" ]; then
    return
fi

if [ $(should_pull "$(get_local_time)" "$(get_upstream_time)" "$(date -u)") == "true" ]; then
    echo "Local mirror is out of date, pulling from upstream mirror. Upstream date: $(get_upstream_time), Local date: $(get_local_time) - current date: $(date -u)"
    cd ${MIRROR_DIRECTORY}
    /home/mirrors/bin/ftpsync sync:all
else
    echo "Local mirror is up to date. Upstream date: $(get_upstream_time), Local date: $(get_local_time) - current date: $(date -u)"
fi

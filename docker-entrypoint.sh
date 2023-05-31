#!/bin/sh

set -e

case "$1" in
    *.yaml|*.yml) set -- registry serve "$@" ;;
    serve|garbage-collect|help|-*) set -- registry "$@" ;;
esac

# Initialize registry monitor
exec monitor /var/lib/registry /home/action.sh /home/cleanup.sh > /var/log/registry_monitor.log 2>&1 &

exec "$@"

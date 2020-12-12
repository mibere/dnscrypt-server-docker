#! /usr/bin/env bash

# if COMMAND is --full-restart, the script is run twice,
# first with the stop command, then with the start command

sleep 180

for service in redis-server; do
    service "$service" status || service "$service" --full-restart
done

for service in unbound encrypted-dns; do
    sv check "$service" || sv force-restart "$service"
done

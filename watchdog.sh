#! /usr/bin/env bash

sleep 180

for service in cron redis-server; do
    service "$service" status || service "$service" --full-restart
done

for service in unbound encrypted-dns; do
    sv check "$service" || sv force-restart "$service"
done

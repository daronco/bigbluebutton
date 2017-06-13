#!/bin/bash
sed -i "s/redis_host:.*/redis_host: ${REDIS_HOST:-127.0.0.1}/g" ../scripts/bigbluebutton.yml
sed -i "s/redis_port:.*/redis_port: ${REDIS_PORT:-6379}/g" ../scripts/bigbluebutton.yml
exec "$@"

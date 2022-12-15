#!/usr/bin/env sh
# Copyright (c) 2022 Tailscale Inc & AUTHORS All rights reserved.
# Use of this source code is governed by a BSD-style
# license that can be found in the LICENSE file.

export PATH=$PATH:/tailscale/bin

TS_AUTH_KEY="${TS_AUTH_KEY:-}"
TS_EXTRA_ARGS="${TS_EXTRA_ARGS:-}"
TS_USERSPACE="${TS_USERSPACE:-true}"
TS_STATE_DIR="${TS_STATE_DIR:-}"
TS_ACCEPT_DNS="${TS_ACCEPT_DNS:-false}"
TS_SOCKS5_SERVER="${TS_SOCKS5_SERVER:-}"
TS_TAILSCALED_EXTRA_ARGS="${TS_TAILSCALED_EXTRA_ARGS:-}"
TS_SOCKET="${TS_SOCKET:-/var/run/tailscale/tailscaled.sock}"

# set -e

TAILSCALED_ARGS="--socket=${TS_SOCKET}"
TAILSCALED_ARGS="${TAILSCALED_ARGS} --state=mem: --statedir=/tmp"

if [[ "${TS_USERSPACE}" == "true" ]]; then
  TAILSCALED_ARGS="${TAILSCALED_ARGS} --tun=userspace-networking"
else
  if [[ ! -d /dev/net ]]; then
    mkdir -p /dev/net
  fi

  if [[ ! -c /dev/net/tun ]]; then
    mknod /dev/net/tun c 10 200
  fi
fi

if [[ ! -z "${TS_TAILSCALED_EXTRA_ARGS}" ]]; then
  TAILSCALED_ARGS="${TAILSCALED_ARGS} ${TS_TAILSCALED_EXTRA_ARGS}"
fi

handler() {
  echo "Caught SIGINT/SIGTERM, shutting down tailscaled"
  kill -s SIGINT $PID
  wait ${PID}
}

echo "Starting tailscaled"
tailscaled ${TAILSCALED_ARGS} &
PID=$!
trap handler SIGINT SIGTERM

HOSTNAME="${FLY_APP_NAME}-${FLY_REGION}-$(hostname)"
UP_ARGS="--accept-dns=${TS_ACCEPT_DNS} --hostname=${HOSTNAME}"
if [[ ! -z "${TS_AUTH_KEY}" ]]; then
  UP_ARGS="--authkey=${TS_AUTH_KEY} ${UP_ARGS}"
fi
if [[ ! -z "${TS_EXTRA_ARGS}" ]]; then
  UP_ARGS="${UP_ARGS} ${TS_EXTRA_ARGS:-}"
fi

echo "Running tailscale up"
tailscale --socket="${TS_SOCKET}" up ${UP_ARGS}

if [[ ! -z "${TS_DEST_IP}" ]]; then
  echo "Adding iptables rule for DNAT"
  iptables -t nat -I PREROUTING -d "$(tailscale --socket=${TS_SOCKET} ip -4)" -j DNAT --to-destination "${TS_DEST_IP}"
fi
echo "Waiting for tailscaled to exit"

echo "allow *.*.*.*" > /etc/rinetd.conf
echo "logfile /dev/stdout" >> /etc/rinetd.conf
echo "0.0.0.0  80   $(tailscale ip -4 nginx)   80" >> /etc/rinetd.conf
echo "0.0.0.0  443  $(tailscale ip -4 nginx)   443" >> /etc/rinetd.conf

rinetd -f -c /etc/rinetd.conf &
wait ${PID}

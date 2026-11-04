#!/usr/bin/env bash
# Demonstrate load balancing: send N HTTPS requests to the load balancer and
# count how many were served by each VM.
#
# Usage: ./test-lb.sh <lb-dns-or-ip> [number-of-requests]
# Note: -k accepts the self-signed certificate used in the lab.
set -euo pipefail

LB="${1:?Usage: $0 <lb-dns-or-ip> [requests]}"
N="${2:-20}"

for i in $(seq 1 "$N"); do
  host=$(curl -sk --max-time 5 "https://${LB}/whoami" | sed -E 's/.*"hostname": *"([^"]+)".*/\1/' | tr -d '\n')
  echo "request $i -> ${host:-FAILED}"
done | tee /dev/stderr | awk '{print $NF}' | sort | uniq -c | sed 's/^/summary: /'

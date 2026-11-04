#!/usr/bin/env bash
set -Eeuo pipefail
trap 'printf "Provisioning failed at line %s.\n" "$LINENO" >&2' ERR

printf 'Starting Managed DevOps Pools provisioning on %s.\n' "$(hostname)"
uname -a

sudo -n install -d -m 0755 /opt/mdp-provisioning
printf 'Managed DevOps Pools provisioning completed.\n' |
  sudo -n tee /opt/mdp-provisioning/ready.txt

printf 'Provisioning completed successfully.\n'

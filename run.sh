#!/usr/bin/env bash
set -euo pipefail

export AWS_ACCESS_KEY_ID=
export AWS_SECRET_ACCESS_KEY=
export AWS_DEFAULT_REGION=

cd /home/joe-doe/tmp/listener-and-rules

make apply

GIT_SSH_COMMAND="ssh -i ~/.ssh/id_ed25519_kinfol" git push -u origin master
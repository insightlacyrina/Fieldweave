#!/bin/zsh
set -e
cd "${0:A:h}"
if [[ ! -d dist/FieldWeave.app ]]; then ./scripts/build-app.sh; fi
open dist/FieldWeave.app

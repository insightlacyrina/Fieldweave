#!/bin/zsh
set -e
cd "${0:A:h}"
./scripts/build-app.sh
open dist/FieldWeave.app

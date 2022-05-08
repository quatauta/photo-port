#!/bin/bash

test -d .asdf || git clone --depth=1 https://github.com/asdf-vm/asdf.git "${ASDF_DIR}" --branch "v${ASDF_VERSION}"
# shellcheck disable=SC1091
source .asdf/asdf.sh
asdf --version

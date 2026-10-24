#!/usr/bin/env bash
# Download the Robo Cat Action Chapter 8 sample code from the authors' public repository.
# The code has no license, so we link to it and do not commit a copy.
# Usage: fetch-sample-code.sh [destination-dir]
#   Default destination: .cache/MultiplayerBook next to this script (git-ignored).
set -euo pipefail

REPO=https://github.com/MultiplayerBook/MultiplayerBook.git
COMMIT=684044a6eca80859fc4d9a69394702059476a7ff
DEST="${1:-$(cd "$(dirname "$0")" && pwd)/.cache/MultiplayerBook}"

if [ ! -d "$DEST/.git" ]; then
    git clone --filter=blob:none --no-checkout "$REPO" "$DEST"
fi
git -C "$DEST" sparse-checkout set "Chapter 8/RoboCatAction"
git -C "$DEST" checkout --quiet "$COMMIT"
echo "Sample code is in $DEST/Chapter 8/RoboCatAction"

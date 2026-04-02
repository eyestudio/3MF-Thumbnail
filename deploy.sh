#!/bin/bash
set -e
SRC=$(find ~/Library/Developer/Xcode/DerivedData -path "*/3MF_Thumbnail-*/Build/Products/Debug/3MF Thumbnail.app" -maxdepth 5 2>/dev/null | head -1)
if [ -z "$SRC" ]; then
    echo "Error: Cannot find built app"
    exit 1
fi
echo "Source: $SRC"
sudo rm -rf "/Applications/3MF Thumbnail.app"
sudo cp -R "$SRC" /Applications/
open "/Applications/3MF Thumbnail.app"
qlmanage -r
killall QuickLookUIService 2>/dev/null || true
echo "Done!"

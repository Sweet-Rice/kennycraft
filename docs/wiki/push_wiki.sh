#!/usr/bin/env bash
# Run from this folder after creating any first page in the repo's Wiki tab.
set -e
git clone https://github.com/Sweet-Rice/kennycraft.wiki.git ../kennycraft.wiki
cp Home.md _Sidebar.md Shared.md Tai.md Tai_2.md Kenny.md Bennett.md ../kennycraft.wiki/
cd ../kennycraft.wiki
git add -A
git commit -m "KennyCraft design doc"
git push

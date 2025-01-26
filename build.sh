#!/bin/bash

clear

if pgrep -x "zig" > /dev/null; then
    echo "Waiting for other build to finish ..."
    while pgrep -x "zig" > /dev/null; do
        sleep 0.1
    done
fi

zig build -freference-trace=100 && zig-out/bin/game

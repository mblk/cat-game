#!/bin/bash

clear

zig build -freference-trace=100 && zig-out/bin/game


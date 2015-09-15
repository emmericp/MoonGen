#!/bin/bash
(
cd $(dirname "${BASH_SOURCE[0]}")
../../build/MoonGen perf-mac.lua 14 15
)

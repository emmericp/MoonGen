#!/bin/bash
(
cd $(dirname "${BASH_SOURCE[0]}")

if ! (which busted 2>&1 > /dev/null)
then
	echo "ERROR: unit tests require busted: https://github.com/Olivine-Labs/busted"
	exit 1
fi
[[ ! -e ../../build/MoonGen ]] && echo "ERROR: MoonGen binary not found. Compile MoonGen first." && exit 1


busted $@ --pattern=^test .
)

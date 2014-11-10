#!/bin/bash
(
cd $(dirname "${BASH_SOURCE[0]}")

if ! (which busted 2>&1 > /dev/null)
then
	echo "ERROR: unit tests require busted: https://github.com/Olivine-Labs/busted"
	exit 1
fi
[[ ! -e ../build/MoonGen ]] && echo "ERROR: MoonGen binary not found. Compile MoonGen first." && exit 1
function exec() {
	shift 2
	# TODO: pass command line args and use a .busted file to separate tests
	../build/MoonGen $@ --pattern=^test .
}
source $(which busted)
)

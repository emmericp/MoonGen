#!/bin/bash
(
cd $(dirname "${BASH_SOURCE[0]}")

if ! (which busted 2>&1 > /dev/null)
then
	echo "ERROR: unit tests require busted: https://github.com/Olivine-Labs/busted"
	exit 1
fi

# TODO: obviously not the best way to do this.
if [[ -e ../build/MoonGen ]]
then
	MOONGEN=../build/MoonGen
elif [[ -e ../../build/MoonGen ]]
then
	MOONGEN=../../build/MoonGen
else
	echo "ERROR: MoonGen binary not found. Compile MoonGen first." && exit 1
fi

# seems to be the 'best' way to use busted with a program that basically behaves like a lua interpreter
function exec() {
	shift 2
	# TODO: pass command line args and use a .busted file to separate tests
	$MOONGEN $@ --pattern=^test .
}
source $(which busted)
)

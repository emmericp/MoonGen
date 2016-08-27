#!/bin/bash

(
cd $(dirname "${BASH_SOURCE[0]}")
cd phobos
if [[ -e setup-hugetlbfs.sh ]] ; then
	ERROR_MSG_SUBDIR="phobos/" ./bind-interfaces.sh
else
	echo "Phobos not found. Please run git submodule update --init --recursive"
fi
)


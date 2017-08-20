#!/bin/bash

(
cd $(dirname "${BASH_SOURCE[0]}")
cd libmoon
if [[ -e setup-hugetlbfs.sh ]] ; then
	ERROR_MSG_SUBDIR="libmoon/" ./bind-interfaces.sh "$@"
else
	echo "libmoon not found. Please run git submodule update --init --recursive"
fi
)


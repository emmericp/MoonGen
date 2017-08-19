#!/bin/bash

(
cd $(dirname "${BASH_SOURCE[0]}")

#update and init only libmoon, libmoons build.sh will do the rest recursivly
git submodule update --init


(
cd libmoon
./build.sh $@ --moongen
)

)


#!/bin/bash

hist_base=$1

if [ "$#" -lt 2 ] || [ ${hist_base:0:1} == "-" ] ; then
    echo "usage: l2-cbr-ipt-runner.sh <histfile_base> <other_arguments_for_lus_script...>"
	exit
fi

declare rates=("10" "20" "40" "80" "160" "320" "640" "1000")
declare sizes=("1400" "688" "332" "154" "65" "60")

# get the path where this script is
dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
echo $dir

for size in "${sizes[@]}"
do
	for rate in "${rates[@]}"
	do
		sudo $dir/../build/MoonGen $dir/../examples/l2-cbr-load-ipt.lua -r $rate -s $size "${@:2}"
		$dir/../normalizer-ipt.pl histogram.csv > $hist_base-r$rate-s$size.csv
		#echo $rate $hist_base"-r"$rate"-s"$size".csv"
		#echo "${@:2}"
	done
done




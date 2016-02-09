#!/bin/bash

#Color Codes
WHI='\033[1;37m'
RED='\033[0;31m'
GRE='\033[0;32m'
ORA='\033[0;33m'
NON='\033[0m'

#Log File Path
logfile='logs/log'$(date '+%Y-%m-%d:%H:%M:%S')'.txt'

#Test Script List
list=$(ls tests/*.lua)

#Relative Moongen Exec Path
path='../build/MoonGen'

#Validate Configuration
if [ -e config/tconfig.lua ]
then
	printf "${WHI}[INFO] Configuration file found.${NON}\n"
	read -r -p "Restart configuration? (Y\N): " response
	response=${response,,}

	if [[ $response =~ ^(yes|y)$ ]]
	 then
		bash config/autoconfig.sh
	fi
else
	bash config/autoconfig.sh
fi

#----------------------------#
#-Execute Tests and evaluate-#
#----------------------------#

tests=$(expr 0)
fails=$(expr 0)
failt=$(expr 0)
utest=$(expr 0)

for script in $list
do
	printf "${WHI}[INFO] Running $script${NON}\n"
	echo "[INFO] Running $script" >> $logfile
	output=$(eval $path $script)
	echo "$output" >> $logfile
	echo "$output" > 'temp.txt'
	result=$(sed -n '/Ran [0-9]* tests in [0-9]*.[0-9]* seconds/,$p' < temp.txt)

	echo "$result" > result.txt

	utest=$(($utest + 1))
	ltests=$(sed -r 's/.*Ran ([0-9]*).*|.*/\1/g' < result.txt)
	tests=$(($tests + $ltests))
	lfails=$(sed -r 's/.*failures=([0-9]*).*|.*/\1/g' < result.txt)
	lfails=$(($lfails + 0))
	fails=$(($fails + $lfails))

	if [ "$lfails" -gt 0 ]
	then
		printf "${RED}[INFO] Ran $ltests tests. $lfails failed!${NON}\n"
		failt=$(expr $failt + 1)
	else
		printf "${GRE}[INFO] Ran $ltests tests successfully!${NON}\n"
	fi

	unset lfails
	unset ltests
	rm result.txt
	rm temp.txt
done

printf "${WHI}[INFO] Ran a total of $tests tests in $utest unit test cases.${NON}\n"
if [ "$fails" -gt 0 ]
then
	printf "${RED}[INFO] A total of $fails failures in $failt unit test cases occured.\n${ORA}[WARN] Please check the corresponding log file: $logfile${NON}\n"
else
	printf "${GRE}[INFO] No failures detected. Everything running smoothly!${NON}\n"
fi

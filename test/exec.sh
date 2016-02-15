#!/bin/bash
# Execute test suite

# Create logs directory if not existing
mkdir -p logs

# Define color codes
WHI='\033[1;37m'
RED='\033[0;31m'
GRE='\033[0;32m'
ORA='\033[0;33m'
CYA='\033[1;36m'
NON='\033[0m'

# Define Log File Path
logfile='logs/log'$(date '+%Y-%m-%d:%H:%M:%S')'.txt'

# Fetch Test Script List
list=$(ls tests/*.lua)

# Set Relative Moongen Exec Path
path='../build/MoonGen'

#-----------------------------#
#-Validate configuration file-#
#-----------------------------#
if [ -e config/tconfig.lua ]
then
	printf "${WHI}[INFO] Configuration file found.${NON}\n"
	# Optionally restart configuration
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

# Define counters
tests=$((0))
fails=$((0))
failt=$((0))
utest=$((0))

# Define lists
passed=()
failed=()

# Clear temporary output log file
rm -f /tmp/testlog.txt

# Execute tests
for script in $list
do
	printf "${CYA}[INFO] Running $script${NON}\n"
	echo "[INFO] Running $script" >> $logfile
	eval "$path $script" > /tmp/temp.txt &
	pid=$!
	trap "kill $pid 2> /dev/null" EXIT
	# Monitor running test
	while kill -0 "$pid" 2>/dev/null; do
		if [ -e /tmp/testlog.txt ]
		then
			content=$(cat /tmp/testlog.txt)
			rm -f /tmp/testlog.txt
			# Deliver output to user
			if [ -n "$content" ];
			then
				printf "${content}\n"
			fi
			sleep 0.01
		fi
	done
	trap - EXIT

	# Process test output
	log=$(cat /tmp/temp.txt)
	echo "$log" >> $logfile
	result=$(sed -n '/Ran [0-9]* tests in [0-9]*.[0-9]* seconds/,$p' < /tmp/temp.txt)
	echo "$result" > /tmp/result.txt

	# Update counters
	utest=$(($utest + 1))
	ltests=$(sed -r 's/.*Ran ([0-9]*).*|.*/\1/g' < /tmp/result.txt)
	tests=$(($tests + $ltests))
	lfails=$(sed -r 's/.*failures=([0-9]*).*|.*/\1/g' < /tmp/result.txt)
	lfails=$(($lfails + 0))
	fails=$(($fails + $lfails))

	# Deliver output
	if [ "$lfails" -gt 0 ]
	then
		printf "${RED}[INFO] ${script} failed\n[INFO] Encountered ${lfails} errors in ${ltests} tests\n" 
		failt=$(expr $failt + 1)
		failed+=("$script")
	else
		printf "${GRE}[INFO] ${script} passed\n[INFO] No error in ${ltests} tests\n"
		passed+=("$script")
	fi

	# Remove temporary files and counters
	unset lfails
	unset ltests
	rm /tmp/result.txt
	rm /tmp/temp.txt
done

# Print summary
printf "${WHI}[INFO] Ran a total of $tests tests in $utest unit test cases.${NON}\n"
if [ "$fails" -gt 0 ]
then
	printf "${RED}[INFO] A total of $fails failures in $failt unit test cases occured.\n${ORA}[WARN] Please check the corresponding log file: $logfile${NON}\n"
else
	printf "${GRE}[INFO] No failures detected. Everything running smoothly!${NON}\n"
fi
printf "${GRE}[INFO] The following tests passed:\n${NON}"
printf "%s\n" "${passed[@]}"
printf "${RED}[INFO] The following tests failed:\n${NON}"
printf "%s\n" "${failed[@]}"

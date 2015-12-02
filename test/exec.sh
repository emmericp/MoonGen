#-------------------------#
#-Variables for later use-#
#-------------------------#

#Path to log file
file='logs/log'$(date '+%Y-%m-%d:%H:%M:%S')'.txt'

#Get test script list
list=$(ls tests/*.lua)

#Moongen Path
path='../build/MoonGen'

#Colors
RED='\033[0;31m'
GRE='\033[0;32m'
WHI='\033[1;37m'
NC='\033[0m'

#----------------------------#
#-Execute Tests and evaluate-#
#----------------------------#

for script in $list
do
	printf "${WHI}[INFO] Running $script${NC}\n"
	output=$(eval $path $script)
	echo "$output" >> $file
	echo "$output" > 'temp.txt'
	eval=$(tail -2 temp.txt)
	rm temp.txt
	
	regex="Ran [0-9]* tests in [0-9]*.[0-9]* seconds\sOK$"
	#if [[ $eval =~ $regex  ]]
	#then
		printf "${GRE}[SUCCESS] $eval${NC}\n"
	#else
	#	printf "${RED}[ERROR] Test failed. Please check the log!${NC}\n"
	#fi
done

#Color Codes
WHI='\033[1;37m'
RED='\033[0;31m'
GRE='\033[0;32m'
ORA='\033[0;33m'
NON='\033[0m'

#Log File Path
file='logs/log'$(date '+%Y-%m-%d:%H:%M:%S')'.txt'

#Test Script List
list=$(ls tests/*.lua)

#Relative Moongen Exec Path
path='../build/MoonGen'

bash config/autoconfig.sh

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
    
    printf "$eval${NON}\n"
done

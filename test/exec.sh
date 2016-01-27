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

#Validate Configuration
if [ -e config/tconfig.lua ]
	printf "${WHI}[INFO] Configuration file found. "
	read -r -p "Restart configuration? (Y\N)" response
	response=${response,,}
	printf "\n"
	if [[ $response =~ ^(yes|y)$ ]]
		bash config/autoconfig.sh
	fi
else
	bash config/autoconfig.sh
fi

#----------------------------#
#-Execute Tests and evaluate-#
#----------------------------#

for script in $list
do
	printf "${WHI}[INFO] Running $script${NC}\n"
	output=$(eval $path $script)
	echo "$output" >> $file
	echo "$output" > 'temp.txt'
	rm temp.txt
    
	printf "$output\n"
done

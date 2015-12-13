#Color Codes
WHI='\033[1;37m'
RED='\033[0;31m'
GRE='\033[0;32m'
ORA='\033[0;33m'
NON='\033[0m'

#Functions
function join { local IFS="$1"; shift; echo "$*"; }

#Start
printf "${WHI}[INFO] Starting configuration.${NON}\n"

rm -f tconfig.lua
echo 'local tconfig = {}' >> tconfig.lua

#--------------------------#
#-Get devices from MoonGen-#
#--Fecht output          --#
#--Strip devices out     --#
#--Format                --#
#--Write to config       --#
#--------------------------#

printf "${WHI}[INFO] Detecting available network ports and cards.${NON}\n"

#--Fetch
output=$(../../build/MoonGen devices.lua)
rm -f devices.txt
echo "$output" > devices.txt

#--Strip
sed -n -E -i -e '/(.*Found.*)/,$ p' devices.txt
sed -i '1 d' devices.txt

#--Format
$crds=()
i=$(expr 0)
j=$(expr 0)
while read line
do
	printf "${line}\n"
	i=$(expr $i + 1)
	adr='00:00:00:00:00:00'
	prt='-1'
	arr=$(echo $line | tr " " "\n")
	for part in $arr
	do
		if [[ $part =~ ^[0-9]*:$ ]];
		then
			prt=${part::-1}
		elif [[ $part == **":"**":"**":"**":"**":"** ]];
		then
			adr=$part
		fi
	done
	if [ "$prt" -ne '-1' ]
	then
		j=$(expr $j + 1)
		crds+=("{$prt,\"$adr\"}")
	fi
done < devices.txt

#--Write
if [ $i -eq 0 ]
then
	printf "${RED}[FAIL] Detected 0 ports! Autoconfig terminated.${NON}\n"
	exit
else
	printf "${GRE}[SUCCESS] Detected ${j} port(s).\n"
fi

cards=$(join , "${crds[@]}")
echo "local cards = {$cards}" >> tconfig.lua
echo "function tconfig.cards()" >> tconfig.lua
echo -e "\treturn cards" >> tconfig.lua
echo 'end' >> tconfig.lua

rm devices.txt

#--Temporarily finalize tconfig.lua
echo "return tconfig" >> tconfig.lua

#---------------------------------#
#-Fetch device speed from MoonGen-#
#---------------------------------#

printf "${WHI}[INFO] Detecting network cards.${NON}\n"

#--Fetch Output
output=$(../../build/MoonGen speed.lua)
rm -f speed.txt
echo "$output" > speed.txt

#--Strip
sed -n -E -i -e '/(.*to come up.*)/,$ p' speed.txt
sed -i '1 d' speed.txt
sed -i '$ d' speed.txt

#--Format
k=$(expr 0)
while read line
do
	#TODO: Filter all mal-formated lines
	printf "$line\n"
	speed=$(echo "$line" | sed -r 's#(.*:.* )([0-9]*)( MBit/s.*)#\2#g')
	if [ $speed  -gt 0 ];
	then
		crds[${k}]= {"$crds[{k}]"::-1}","$speed"}"
		k=$(expr $k + 1)
	fi
done < speed.txt
cards=$(join , "${crds[@]}")

if [ $i -eq $k ]
then
	printf "${GRE}[SUCCESS] Detected ${k} card(s).${NON}\n"
elif [ $k -eq 0 ]
then
	printf "${RED}[FAIL] Detected 0 cards! Autoconfig terminated.${NON}\n"
	exit
else
	l=$(expr $i - $k)
	printf "${ORA}[WARN] Detected ${k} card(s). ${l} port(s) empty.${NON}\n"
fi

rm -f speed.txt

#--Store
rm -f tconfig.lua
echo -e "local tconfig = {}\n" >> tconfig.lua
echo -e "local cards = {$cards}\n" >> tconfig.lua
echo 'function tconfig.cards()' >> tconfig.lua
echo -e "\treturn cards" >> tconfig.lua
echo -e "end\n" >> tconfig.lua
echo 'return tconfig' >> tconfig.lua

#---------------------#
#-Gather device-pairs-#
#---------------------#

printf "${WHI}[INFO] Detecting network card pairs.${NON}\n"

#--Fetch Output
output=$(../../build/MoonGen pairs.lua)
rm -f pairs.txt
echo "$output" > pairs.txt

#--Strip
sed -n -E -i -e '/(.*devices are up.*)/,$ p' pairs.txt
sed -i '1 d' pairs.txt

#--Format
pairs=()
while read line
do
	if [[ $line == **":"**":"**":"**":"**":"**" - "**":"**":"**":"**":"**":"** ]]
	then
		mac1=$(echo "$line" | sed -r 's#^(..:..:..:..:..:..).*#\1#g')
		mac2=$(echo "$line" | sed -r 's#.*(..:..:..:..:..:..)$#\1#g')
		mac1=$(echo "$mac1" | tr '[:lower:]' '[:upper:]')
		printf "${WHI}[INFO] Detected: ${mac1} -> ${mac2}${NON}\n"
		port1=$(echo "$cards" | sed -r "s#.*\{([0-9]*),\"$mac1\",([0-9]*)\}.*#\1#g")
		port2=$(echo "$cards" | sed -r "s#.*\{([0-9]*),\"$mac2\",([0-9]*)\}.*#\1#g")

		if [[ "$port1" =~ ^-?[0-9]+$ ]] && [[ "$port2" =~ ^-?[0-9]+$ ]]
		then
			#-Order Ports
			if [ "$port1" -gt "$port2" ]
			then
				port3=$port1
				port1=$port2
				port2=$port3
			fi
			pair="{$port1,$port2}"
			printf "${WHI}[INFO] Pairing: $port1 - $port2${NON}\n"

			#-Save Pairing if not already in existence
			if ! [[ " ${pairs[@]} " =~ " ${pair} " ]]
			then
				pairs+=($pair)
			fi
		else
			printf "${ORA}[WARN] Not a pairing within the system.${NON}\n"
		fi
	fi
done < pairs.txt

pairs=$(join , "${pairs[@]}")
echo "$pairs"

#--Store
#TODO

printf "${GRE}[SUCCESS] Configuration successful.${NON}\n"

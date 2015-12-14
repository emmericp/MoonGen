#Color Codes
WHI='\033[1;37m'
RED='\033[0;31m'
GRE='\033[0;32m'
ORA='\033[0;33m'
NON='\033[0m'

#Functions
function join { local IFS="$1"; shift; echo "$*"; }

#Directory
dir="$(dirname "$0")"

#Start
printf "${WHI}[INFO] Starting configuration.${NON}\n"

rm -f $dir/tconfig.lua
echo 'local tconfig = {}' >> $dir/tconfig.lua

#--------------------------#
#-Get devices from MoonGen-#
#--Fecht output          --#
#--Strip devices out     --#
#--Format                --#
#--Write to config       --#
#--------------------------#

printf "${WHI}[INFO] Detecting available network ports and cards.${NON}\n"

#--Fetch
output=$($dir/../../build/MoonGen $dir/devices.lua $dir)
rm -f $dir/devices.txt
echo "$output" > $dir/devices.txt

#--Strip
sed -n -E -i -e '/(.*Found.*)/,$ p' $dir/devices.txt
sed -i '1 d' $dir/devices.txt

#--Format
crds=()
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
done < $dir/devices.txt

#--Write
if [ $i -eq 0 ]
then
	printf "${RED}[FAIL] Detected 0 ports! Autoconfig terminated.${NON}\n"
	exit
else
	printf "${GRE}[SUCCESS] Detected ${j} port(s).\n"
fi

cards=$(join , "${crds[@]}")
echo "local cards = {$cards}" >> $dir/tconfig.lua
echo "function tconfig.cards()" >> $dir/tconfig.lua
echo -e "\treturn cards" >> $dir/tconfig.lua
echo 'end' >> $dir/tconfig.lua

rm $dir/devices.txt

#--Temporarily finalize tconfig.lua
echo "return tconfig" >> $dir/tconfig.lua

#---------------------------------#
#-Fetch device speed from MoonGen-#
#---------------------------------#

printf "${WHI}[INFO] Detecting network cards.${NON}\n"

#--Fetch Output
output=$($dir/../../build/MoonGen $dir/speed.lua $dir)
rm -f $dir/speed.txt
echo "$output" > $dir/speed.txt
rm $dir/tconfig.lua

#--Strip
sed -n -E -i -e '/(.*to come up.*)/,$ p' $dir/speed.txt
sed -i '1 d' $dir/speed.txt
sed -i '$ d' $dir/speed.txt

#--Format
k=$(expr 0)
while read line
do
	#TODO: Filter all mal-formated lines
	printf "$line\n"
	speed=$(echo "$line" | sed -r 's#(.*:.* )([0-9]*)( MBit/s.*)#\2#g')
	if [ $speed  -gt 0 ];
	then
		crd=${crds[${k}]}
		crds[${k}]=$(echo "${crd::-1},$speed}")
		k=$(expr $k + 1)
	fi
done < $dir/speed.txt
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
	printf "${GRE}[SUCESS] Detected ${k} card(s).${NON}\n${ORA}[WARN] ${l} port(s) empty.${NON}\n"
fi

rm -f $dir/speed.txt

#--Store
rm -f $dir/tconfig.lua
echo -e "local tconfig = {}\n" >> $dir/tconfig.lua
echo -e "local cards = {$cards}\n" >> $dir/tconfig.lua
echo 'function tconfig.cards()' >> $dir/tconfig.lua
echo -e "\treturn cards" >> $dir/tconfig.lua
echo -e "end\n" >> $dir/tconfig.lua
echo 'return tconfig' >> $dir/tconfig.lua

#---------------------#
#-Gather device-pairs-#
#---------------------#

printf "${WHI}[INFO] Detecting network card pairs.${NON}\n"

#--Fetch Output
output=$($dir/../../build/MoonGen $dir/pairs.lua $dir)
rm -f $dir/pairs.txt
echo "$output" > $dir/pairs.txt

#--Strip
sed -n -E -i -e '/(.*devices are up.*)/,$ p' $dir/pairs.txt
sed -i '1 d' $dir/pairs.txt

#--Format
pairs=()
n=$(expr 0)
while read line
do
	if [[ $line == **":"**":"**":"**":"**":"**" - "**":"**":"**":"**":"**":"** ]]
	then
		mac1=$(echo "$line" | sed -r 's#^(..:..:..:..:..:..).*#\1#g')
		mac2=$(echo "$line" | sed -r 's#.*(..:..:..:..:..:..)$#\1#g')
		mac1=$(echo "$mac1" | tr '[:lower:]' '[:upper:]')
		printf "${WHI}[INFO] Detected: ${mac1} -> ${mac2}${NON}\n"
		port1=$(echo "$cards" | sed -r "s#.*\{([0-9]*),\"$mac1\".*#\1#g")
		port2=$(echo "$cards" | sed -r "s#.*\{([0-9]*),\"$mac2\".*#\1#g")

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
				n=$(expr $n + 1)
				pairs+=($pair)
			fi
		else
			printf "${ORA}[WARN] Not a pairing within the system.${NON}\n"
		fi
	fi
done < $dir/pairs.txt

pairs=$(join , "${pairs[@]}")

#--Store
#rm -f $dir/pairs.txt
sed -i '$ d' $dir/tconfig.lua

echo "local pairs = {$pairs}" >> $dir/tconfig.lua
echo -e "\nfunction tconfig.pairs()" >> $dir/tconfig.lua
echo -e "\treturn pairs" >> $dir/tconfig.lua
echo -e "end\n" >> $dir/tconfig.lua
echo "return tconfig" >> $dir/tconfig.lua

printf "${GRE}[SUCCESS] Detected $n pairs.${NON}\n"
printf "${GRE}[SUCCESS] Configuration successful.${NON}\n"

WHI='\033[1;37m'
NON='\033[0m'

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
		crds="$crds{$prt,\"$adr\"},"
	fi
done < devices.txt
crds=${crds::-1}

#--Write
RED='\033[0;31m'
GRE='\033[0;32m'
ORA='\033[0;33m'

if [ $i -eq 0 ]
then
	printf "${RED}[FAILURE] Detected 0 ports! Autoconfig terminated.${NON}\n"
	exit
else
	printf "${GRE}[SUCCESS] Detected ${j} port(s).\n"
fi

echo "local cards = {$crds}" >> tconfig.lua
echo "function tconfig.cards()" >> tconfig.lua
echo -e "\treturn cards" >> tconfig.lua
echo 'end' >> tconfig.lua

rm devices.txt

#--Temporarily finalize tconfig.lua
echo "return tconfig" >> tconfig.lua

#---------------------------------#
#-Fetch device speed from MoonGen-#
#--Fetch output                 --#
#--Strip speed per device       --#
#--Format                       --#
#--Store                        --#
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
crds=$(echo $crds | tr -d '{')
crar=$(echo "${crds::-1}" | sed "s/},/\n/g")
readarray -t crar <<< "$crar"
crds=""
k=$(expr 0)
while read line
do
	printf "$line\n"
	speed=$(echo "$line" | sed -r 's#(.*:.* )([0-9]*)( MBit/s.*)#\2#g')
	if [ $speed  -gt 0 ];
	then 
		crds=$crds"{"${crar[0]}","$speed"},"
		k=$(expr $k + 1)
	fi
	crar=("${crar[@]:1}")
done < speed.txt
crds=${crds::-1}

if [ $i -eq $k ]
then
	printf "${GRE}[SUCCESS] Detected ${k} card(s).${NON}\n"
elif [ $k -eq 0 ]
then
	printf "${RED}[FAILURE] Detected 0 cards! Autoconfig terminated.${NON}\n"
	exit
else
	l=$(expr $i - $k)
	printf "${ORA}[WARNING] Detected ${k} card(s). ${l} port(s) empty.${NON}\n"
fi

rm -f speed.txt

#--Store
rm -f tconfig.lua
echo -e "local tconfig = {}\n" >> tconfig.lua
echo -e "local cards = {$crds}\n" >> tconfig.lua
echo 'function tconfig.cards()' >> tconfig.lua
echo -e "\treturn cards" >> tconfig.lua
echo -e "end\n" >> tconfig.lua
echo 'return tconfig' >> tconfig.lua

printf "${GRE}[SUCCESS] Configuration successful.${NON}\n"

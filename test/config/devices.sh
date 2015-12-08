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
rm devices.txt
echo "$output" > devices.txt

#--Strip
sed -n -E -i -e '/(.*Found.*)/,$ p' devices.txt
sed -i '1 d' devices.txt

#--Format
crds="{"
i=$(expr 0)
j=$(expr 0)
while read line
do
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
crds=${crds::-1}"}"

#--Write
RED='\033[0;31m'
GRE='\033[0;32m'
ORA='\033[0;33m'

printf "${GRE}[SUCCESS] Deteced ${i} available ports.${NON}\n"

if [ $i -eq $j ];
then
	printf "${GRE}[SUCCESS] Detected ${j} network cards.${NON}\n"
else
	l=$(expr $i - $j)
	printf"${ORA}[WARNING] Detected ${j} cards. ${l} ports empty.${NON}\n"
fi

echo "local cards = $crds" >> tconfig.lua
echo "function tconfig.ports()" >> tconfig.lua
echo -e "\treturn ports" >> tconfig.lua
echo 'end' >> tconfig.lua

#---------------------------------#
#-Fetch device speed from MoonGen-#
#---------------------------------#

printf "${WHI}[INFO] Detecting network card speed.${NON}\n"





#-Fin
echo 'return tconfig' >> tconfig.lua

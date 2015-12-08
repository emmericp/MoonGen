#--------------------------#
#-Get devices from MoonGen-#
#--Fecht output		 --#
#--Strip devices out	 --#
#--Format		 --#
#--------------------------#
output=$(../../build/MoonGen devices.lua)
rm devices.txt
echo "$output" > devices.txt
sed -n -E -i -e '/(.*Found.*)/,$ p' devices.txt | sed '1 d'

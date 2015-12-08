#--------------------------#
#-Get devices from MoonGen-#
#--Fecht output		 --#
#--Strip devices out	 --#
#--Format & Store	 --#
#--------------------------#

#--Fetch
output=$(../../build/MoonGen devices.lua)
rm devices.txt
echo "$output" > devices.txt

#--Strip
sed -n -E -i -e '/(.*Found.*)/,$ p' devices.txt
sed -i '1 d' devices.txt

#--Format & Store
while read line
do
	echo "$line"
done < devices.txt

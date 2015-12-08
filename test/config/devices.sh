output=$(../../build/MoonGen devices.lua)
rm devices.txt
echo $output > devices.txt
output=$(sed -e 's/^.*Found/Found/p' devices.txt)
rm devices.txt
echo $output > devices.txt

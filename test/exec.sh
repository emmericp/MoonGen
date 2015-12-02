#-------------------------
#-Variables for later use-
#-------------------------

#Path to log file
file='logs/log'$(date '+%Y-%m-%d:%H:%M:%S')'.txt'

#Get test script list
list=$(ls tests/*.lua)

#Moongen Path
path='../build/MoonGen'

#----------------------------
#-Execute Tests and evaluate-
#----------------------------

for script in $list
do
echo "Running $script"
output=$(eval $path $script)
echo "$output" >> $file
echo "$output" >> 'temp.txt'
eval= tail -2 temp.txt
echo "$eval"
done

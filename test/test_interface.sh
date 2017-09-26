#!/bin/bash
echo -e "Testing error management system. No flow should be able to start.\n"
exec sudo ./build/MoonGen interface/init.lua start -c test/flows f1:1:1:test=1,rate=a valid:100:100 valid:a:b

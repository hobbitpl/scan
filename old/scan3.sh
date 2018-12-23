#!/bin/bash
id=$$

varyear=`date +%Y`
varmonth=`date +%m`
varday=`date +%d`

#data=`date +%Y%m%d`
#data=$year_$month_$day

hour=`date +%H%M`

echo "Ile skanów? [podaj liczbê & ENTER]: "
read ile

x=0
while [ $x -lt $ile ] ;do
#echo "sas" > scan_$data_$hour_$x.jpg
#scanimage --resolution 150 --mode Gray --format=jpeg > scan_$data_$hour_$x.jpg
scanimage --resolution 150 --mode Gray --format=jpeg > scan"_"$varyear"_"$varmonth"_"$varday"_"$hour"_"$x.jpg
let x=x+1
done

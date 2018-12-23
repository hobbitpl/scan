#!/bin/bash
scanPath='/home/meblegama/stuff/temp/tempSkan'

id=$$
varyear=`date +%Y`
varmonth=`date +%m`
varday=`date +%d`
varhour=`date +%H`
varmin=`date +%M`
varsec=`date +%S`

#data=`date +%Y%m%d`
#hour=`date +%H%M%S`



echo "Ile skanów? [podaj liczb¿ & ENTER]: "
read ile

x=0
while [ $x -lt $ile ] ;do
#echo "sas" > scan.$data.$hour.$x.jpg

filename=scan"_"$varyear"_"$varmonth"_"$varday"_"$varhour"_"$varmin"_"$varsec"_"$x.jpg

scanimage --resolution 150 --mode Gray --format=jpeg > $scanPath/$filename
convert -rotate 180 $scanPath/$filename $scanPath/$filename
chmod 664 $scanPath/$filename
let x=x+1
done

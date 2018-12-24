#!/bin/bash

# define your scan output directory
scanPath='/home/hobbit/Obrazy/00_scan_temp/'

id=$$
data=`date +%Y%m%d`
hour=`date +%H%M%S`

echo "Ile skanów? [podaj liczbe & ENTER]: "
read ile

x=0
while [ $x -lt $ile ] ;do
#echo "sas" > scan.$data.$hour.$x.jpg
filename=scan'_'$data'_'$hour'_'$x.jpg
scanimage --resolution 300 --mode Color --format=png > $scanPath/$filename
convert -rotate 0 $scanPath/$filename $scanPath/$filename
chmod 664 $scanPath/$filename
let x=x+1
done

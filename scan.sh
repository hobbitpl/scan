#!/bin/bash
<<<<<<< HEAD

# define your scan output directory
varOutputPath='/home/hobbit/Obrazy/00_scan_temp/'

id=$$
data=`date +%Y%m%d`
hour=`date +%H%M%S`

echo "Ile skanów? [podaj liczbe & ENTER]: "
read ile

x=0
while [ $x -lt $ile ] ;do
#echo "sas" > scan.$data.$hour.$x.jpg
filename=scan'_'$data'_'$hour'_'$x.jpg
scanimage --resolution 300 --mode Color --format=png > $varOutputPath/$filename
convert -rotate 0 $varOutputPath/$filename $varOutputPath/$filename
chmod 664 $varOutputPath/$filename
let x=x+1
done
=======
varOutputPath='/home/meblegama/stuff/temp/tempSkan'

id=$$

varyear=`date +%Y`
varmonth=`date +%m`
varday=`date +%d`
varhour=`date +%H`
varmin=`date +%M`
varsec=`date +%S`
varsite='gama'

#data=`date +%Y%m%d`
#hour=`date +%H%M%S`

x=0

        clear

while :
do
	num=$(printf "%03d" $x)
        read -p "Nacisnij [ ENTER ] aby zeskanowac jedna kartke lub [ CTRL + C ] aby skonczyc skanowanie"
        echo "Rozpoczynam skanowanie..."
	filename="scan@"$varsite"_"$varyear"_"$varmonth"_"$varday"_"$varhour"_"$varmin"_"$varsec"_"$num.jpg
        scanimage --resolution 150 --mode Gray --format=jpeg > $varOutputPath/$filename
        convert -rotate 0 $varOutputPath/$filename $varOutputPath/$filename
        chmod 664 $varOutputPath/$filename
        echo ""
        echo "Skan zrobiony i zapisany pod nazwa: " $filename
        echo ""
        let x=x+1
done

logout

>>>>>>> bd625c1f47c5eca4f2cc58bc1f7ef5d6d917a4e9

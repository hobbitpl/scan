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

x=0

        clear

while :
do
	num=$(printf "%03d" $x)
        read -p "Nacisnij [ ENTER ] aby zeskanowac jedna kartke lub [ CTRL + C ] aby skonczyc skanowanie"
        echo "Rozpoczynam skanowanie..."
		filename=scan"_"$varyear"_"$varmonth"_"$varday"_"$varhour"_"$varmin"_"$varsec"_"$num.jpg
        scanimage --resolution 150 --mode Gray --format=jpeg > $scanPath/$filename
        convert -rotate 0 $scanPath/$filename $scanPath/$filename
        chmod 664 $scanPath/$filename
        echo ""
        echo "Skan zrobiony i zapisany pod nazwa: " $filename
        echo ""
        let x=x+1
done

logout


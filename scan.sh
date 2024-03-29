#!/bin/bash



clear

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

#printf $DIR

. $DIR/local.config


id=$$

var_year=`date +%Y`
var_month=`date +%m`
var_day=`date +%d`
var_hour=`date +%H`
var_min=`date +%M`
var_sec=`date +%S`


#data=`date +%Y%m%d`
#hour=`date +%H%M%S`

x=0

#skanowanie wsadowe - działające
#scanimage --format tiff --batch=$(date +%Y%m%d_%H%M%S)_p%04d.tiff  --resolution 300 --source 'ADF Front'

while :
do
	num=$(printf "%03d" $x)
        read -p "Nacisnij [ ENTER ] aby zeskanowac jedna kartke lub [ CTRL + C ] aby skonczyc skanowanie"
        echo "Rozpoczynam skanowanie..."
	var_filename="scan@"$var_site"_D"$var_year"_"$var_month"_"$var_day"_T"$var_hour"_"$var_min"_"$var_sec"_"$num.jpg
        scanimage --resolution $var_resolution --mode $var_mode --format=$var_format > $var_output_path/$var_filename
        convert -rotate $var_rotate $var_output_path/$var_filename $var_output_path/$var_filename
        chmod 664 $var_output_path/$var_filename
        echo ""
        figlet "skan zapisano" 
        echo "plik:" $var_output_path$var_filename
        echo ""
        let x=x+1
done

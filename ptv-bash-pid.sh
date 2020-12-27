#!/bin/bash
#REMOVES BLINKING CURSOR
tput civis
#INPUT YOUR DEVID AND API KEY HERE
devid=""
apikey=""
baseurl="http://timetableapi.ptv.vic.gov.au"
#STOP FOR WHICH YOU WANT DEPARTURES; 1071 IS FLINDERS STREET
station="1071"
#INITIALISATION MESSAGE
echo "Launching Metro PID for Flinders Street All Platforms...takes around 15-30 seconds..."
#THIS SETS UP AN INFINITE REFRESH LOOP. SLEEP TIME IS AT THE BOTTOM OF THE SCRIPT
i=1
while [ "$i" == 1 ]
do
#GET DEPARTURES; I RECOMMEND SETTING MAX_RESULTS TO '2' (WILL GET NEXT 2 DEPARTURES FOR EACH ROUTE)
query="departures/route_type/0/stop/$station?max_results=2&include_cancelled=false"
signature=$(echo -n "/v3/$query&devid=$devid" | openssl dgst -sha1 -hmac $apikey | sed "s/(stdin)= //";)
url="$baseurl/v3/$query&devid=$devid&signature=$signature"
depdata=$(curl -s $url)
#WRITES RUNIDS TO A TEMP FILE
printf $depdata | jq --raw-output '.departures[] | .run_id' > runids.tmp
#GETS NUMBER OF RUNS IN TEMP FILE; SETS UP A LOOP TO GET DETAILS FOR EACH
lines=$(wc -l < runids.tmp)
if [ $lines -gt 0 ]
then
counter=1
#PRINTS PID HEADER TO ANOTHER TEMP FILE (WILL BE THE END PRODUCT DISPLAYED AT THE END OF EACH REFRESH); SETS COLOUR TO DEFAULT TO OFFSET FROM STOPPING PATTERNS LATER ON
NC='\033[0m'
time=$(date +%H:%M)
printf "${NC}Flinders Street - All Platforms\t\t\t\tTime: $time\n" > pid.tmp
echo ------------------------------ >> pid.tmp
echo >> pid.tmp
printf "%-9s %-20s %-13s %-10s %-12s %-27s %-7s %-8s %s\n" "Scheduled" "Destination" "Pattern" "Live ETA" "Vehicle" "Live Location" "Bearing" "Platform"  >> pid.tmp
printf "%-9s %-20s %-13s %-10s %-12s %-27s %-7s %-8s %s\n" "---------" "-----------" "-------" "--------" "-------" "-------------" "-------" "--------" >> pid.tmp
echo >> pid.tmp
until [ $counter -gt $lines ]
do
#GET PLATFORM; ALTCOUNTER IS NEEDED BECAUSE THE API COUNTS DEPARTURES FROM ZERO
(( altcounter = counter - 1 ))
platform=$(jq --raw-output ".departures[$altcounter] | .platform_number" <<<$depdata)
#GET SCHEDULED DEPARTURE; CONVERT TO LOCAL TIME
schedtime=$(jq --raw-output ".departures["$altcounter"] | .scheduled_departure_utc" <<<$depdata)
fschedtime=$(date -d "$schedtime" +%H:%M)
#GET LIVE DEPARTURE (PTV ESTIMATE)
livetime=$(jq --raw-output ".departures["$altcounter"] | .estimated_departure_utc" <<<$depdata)
#CHECK THAT THE LIVE TIME EXISTS, AND FORMAT CORRECTLY TO 'MINUTES UNTIL'
if [[ $livetime != "null" ]]
then
flivetime=$(date -d "$livetime" +%s)
currenttime=$(date +%s)
(( fflivetime = (flivetime - currenttime) / 60 ))
if [ $fflivetime -lt 0 ]
then
fflivetime="-"
else
if [ $fflivetime == 0 ]
then
fflivetime="NOW"
else
if [ $fflivetime == 1 ]
then
fflivetime="$fflivetime min"
else
fflivetime="$fflivetime mins"
fi
fi
fi
else
fflivetime="-"
fi
#GET PATTERN (DESTDATA) FOR RUN, RETRIEVF DESTINATION NAME
runid=$(awk NR==$counter runids.tmp)
query="pattern/run/$runid/route_type/0?expand=All&stop_id=1071"
signature=$(echo -n "/v3/$query&devid=$devid" | openssl dgst -sha1 -hmac $apikey | sed "s/(stdin)= //";)
url="$baseurl/v3/$query&devid=$devid&signature=$signature"
destdata=$(curl -s $url)
destination=$(jq --raw-output '.runs[] | .destination_name' <<<$destdata)
#GET RUN (VEHDATA), RETRIEVE VEHICLE TYPE
query="runs/$runid?expand=All"
signature=$(echo -n "/v3/$query&devid=$devid" | openssl dgst -sha1 -hmac $apikey | sed "s/(stdin)= //";)
url="$baseurl/v3/$query&devid=$devid&signature=$signature"
vehdata=$(curl -s $url)
vehicle=$(jq --raw-output '.runs[0].vehicle_descriptor.description' <<<$vehdata)
fvehicle=$(cut -d " " -f3 <<<$vehicle)
#USING PATTERN INFO (DESTDATA), DETERMINE STOPPING PATTERN TYPE. I FOUND THAT RUN (VEHDATA) TENDS TO BE LESS ACCURATE FOR SOME REASON
if [[ $fvehicle == "null" ]]
then
fvehicle="-"
fi
express=$(jq --raw-output '.runs[].express_stop_count' <<<$destdata)
if [ $express -gt 4 ]
then
fexp="Express"
else
if [ $express -gt 0 ]
then
fexp="Ltd Express"
else
fexp="Stops All"
fi
fi
#USING RUN (VEHDATA), GET GPS COORDINATES OF VEHICLE
latin=$(jq --raw-output '.runs[0].vehicle_position.latitude' <<<$vehdata)
if [[ $latin != "" ]]
then
if [[ $latin != "null" ]]
then
longin=$(jq --raw-output '.runs[0].vehicle_position.longitude' <<<$vehdata)
query="search/Station?route_types=0&latitude=$latin&longitude=$longin&max_distance=10000"
signature=$(echo -n "/v3/$query&devid=$devid" | openssl dgst -sha1 -hmac $apikey | sed "s/(stdin)= //";)
url="$baseurl/v3/$query&devid=$devid&signature=$signature"
#LOOKUP GPS COORDINATES TO FIND NEAREST TRAIN STATION TO APPROXIMATE NETWORK LOCATION OF VEHICLE
vehloc=$(curl -s $url | jq --raw-output '.stops | min_by(.stop_distance) | .stop_name' | sed '$s/\w*$//')
vehloc="Near $vehloc"
else
vehloc="-"
fi
else
vehloc="-"
fi
#GET BEARING OF VEHICLE AND CONVERT TO CARDINAL DIRECTION; EXACTLY ZERO IS CONSIDERED SAME AS NULL
direction=$(jq --raw-output '.runs[].vehicle_position.bearing' <<<$destdata)
if [[ $direction != "null" && $direction != "0" ]]
then
bearing=$(cut -d "." -f1 <<<$direction)
if [[ $bearing -ge "-45" && $bearing -lt "45" ]]
then
fbearing="North"
else
if [[ $bearing -ge "45" && $bearing -lt "135" ]]
then
fbearing="East"
else
if [[ $bearing -ge "135" && $bearing -lt "225" ]]
then
fbearing="South"
else
if [[ $bearing -lt "-45" || $bearing -ge "225" ]]
then
fbearing="West"
else
fbearing="-"
fi
fi
fi
fi
else
fbearing="-"
fi
#PURGE ANY ENTRIES THAT DIDNT PROVIDE A PLATFORM NUMBER. THESE ONES TEND TO BE BUGGY AND PRODUCE A BUNCH OF NULL RESPONSES
if [[ $platform != "null" ]]
then
#PRINT ENTRY
printf "${NC}%-9s %-20s %-13s %-10s %-12s %-27s %-7s %-8s %s\n" $fschedtime "$destination" "$fexp" "$fflivetime" $fvehicle "$vehloc" "$fbearing" "$platform">> pid.tmp
echo >> pid.tmp
#GET STOPPING PATTERN FOR FIRST TWO DEPARTURES AND PRINT; COLOUR GREY
GREY='\033[1;30m'
if [[ counter -lt 3 ]]
then
stops=$(jq --raw-output '[.stops[].stop_name] | join("_")' <<<$destdata)
fstops=$(printf "$stops" | awk -F'Flinders Street_' '{print $2}' | sed --expression='s/_/\n/g' | column -c 115)
printf "${GREY}$fstops" >> pid.tmp
echo >> pid.tmp
fi
if [[ counter -lt 3 ]]
then
echo >> pid.tmp
fi
fi
(( counter = counter + 1 ))
done
fi
clear
#GET FIRST 75 LINES OF THE PID TEMP FILE FOR DISPLAY. ADJUST ACCORDING TO YOUR SCREEN/WINDOW SIZE
head -n 75 pid.tmp
#DELETE TEMP FILES
rm runids.tmp pid.tmp
#WAIT 25 SECONDS BEFORE REFRESHING
sleep 25
done


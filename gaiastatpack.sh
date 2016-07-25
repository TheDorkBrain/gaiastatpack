#!/bin/bash
reportRoot="/var/statpack"
reportTmp="$reportRoot/tmp"
reportPack="$reportRoot/compressed"

# Function to intercept Ctrl+C
function sighandler {
  echo "Caught Ctrl+C"
  # Remove the pid file
  rm -f "/var/run/$(basename $0).pid"
  # Disable the traps
  trap - SIGINT
}
# Configure traps on SIGINT for Ctrl+C handling
trap sighandler SIGINT

# Create pid file
echo $! > "/var/run/$(basename $0).pid"

# Generate timestamp for use in file names
timestamp=$(date +%Y%m%d-%H%M%S)

# Create necessary directory structure if it's missing'
if [ ! -d "$reportRoot" ]; then mkdir "$reportRoot"; fi
if [ ! -d "$reportTmp" ]; then mkdir "$reportTmp"; fi
if [ ! -d "$reportPack" ]; then mkdir "$reportPack"; fi

# Clean the tmp directory
for file in "$reportTmp/*.csv"; do rm -f $file; done
for file in "$reportTmp/*.tgz"; do rm -f $file; done

# Print CSV headers
printf "\"timestamp\",\"swap location\",\"total KB\",\"free KB\"\n" > "$reportTmp/swap-$timestamp-$USER.csv"
printf "\"timestamp\",\"vmTotal\",\"vmActive\",\"realTotal\",\"realActive\",\"realFree\",\"memSwapsPerSec\",\"memToDiskPerSec\"\n" > "$reportTmp/cpinfo-memory-$timestamp-$USER.csv"
printf "\"timestamp\",\"device\",\"transfersPerSec\",\"blocksReadPerSec\",\"blocksWrittenPerSec\"\n" > "$reportTmp/diskio-$timestamp-$USER.csv"
printf "\"timestamp\",\"oneMinAvg\",\"fiveMinAvg\",\"fifteenMinAvg\"\n" > "$reportTmp/cpuload-$timestamp-$USER.csv"

# Keep collecting stats until the pid file is removed by sighandler
printf "Capturing stats (Ctrl+C to stop) . . .\n"
while [ -f "/var/run/$(basename $0).pid" ]
do
  # Display current date and time to let user know we're still working
  date
  # Get current timestamp
  now=$(date +%Y%m%d-%H:%M:%S)

  # Get swap info
  cat /proc/swaps | tail -n+2 | while read line
  do
    swapLocation=$(echo $line | awk '{FS="[ ]"}; {print $1}')
    swapTotal=$(echo $line | awk '{FS="[ ]"}; {print $3}')
    swapFree=$(echo $line | awk '{FS="[ ]"}; {print $4}')
    printf "\"$now\",\"$swapLocation\",\"$swapTotal\",\"$swapFree\"\n" >> "$reportTmp/swap-$timestamp-$USER.csv"
  done


  # Get memory info from CheckPoint
  ctr=0
  cpstat -f memory os | tail -n+2 | head -n-1 | while read line
  do
    ((ctr++))
    value=$(echo $line | awk '{FS=": "}; {print $NF}')
    case "$ctr" in
      "1")
        vmTotal=$value
        ;;
      "2")
        vmActive=$value
        ;;
      "3")
        realTotal=$value
        ;;
      "4")
        realActive=$value
        ;;
      "5")
        realFree=$value
        ;;
      "6")
        memSwapsPerSec=$value
        ;;
      "7")
        memToDiskPerSec=$value
        printf "\"$now\",\"$vmTotal\",\"$vmActive\",\"$realTotal\",\"$realActive\",\"$realFree\",\"$memSwapsPerSec\",\"$memToDiskPerSec\"\n" >> "$reportTmp/cpinfo-memory-$timestamp-$USER.csv"
        ;;
    esac  
  done

  # Get disk I/O stats
  iostat /dev/{h,s}d* | tail -n+7 | head -n-1 | while read line
  do
    device=$(echo $line | cut -f1 -d$' ')
    transferPerSec=$(echo $line | cut -f2 -d$' ')
    readPerSec=$(echo $line | cut -f3 -d$' ')
    writePerSec=$(echo $line | cut -f4 -d$' ')
    printf "\"$now\",\"$device\",\"$transferPerSec\",\"$readPerSec\",\"$writePerSec\"\n" >> "$reportTmp/diskio-$timestamp-$USER.csv"
  done
  
  # Get CPU stats
  oneMin=$(cat /proc/loadavg | cut -f1 -d$' ')
  fiveMin=$(cat /proc/loadavg | cut -f2 -d$' ')
  fifteenMin=$(cat /proc/loadavg | cut -f3 -d$' ')
  printf "\"$now\",\"$oneMin\",\"$fiveMin\",\"$fifteenMin\"\n" >> "$reportTmp/cpuload-$timestamp-$USER.csv"
  
  sleep 3
done

# Stat collection loop is done, time to create a tgz package
printf "Creating statpack $reportPack/$timestamp-$USER.tgz\n"
pushd "$reportTmp" > /dev/null
tar --remove-files -zcvf $timestamp-$USER.tgz *.csv
mv $timestamp-$USER.tgz $reportPack
popd > /dev/null
# Clean up after ourselves in case something got left behind
for file in "$reportTmp/*.csv"; do rm -f $file; done
printf "Done\n"

#!/bin/sh
##
## A simple script to measure the energy usage of modern laptops during idle
## over longer timespans, allowing to spot small differences made by
## configuration changes or kernel power saving work.
##
## When using this, keep the laptop disconnected from AC during the whole
## measurement and keep system utilization to a minimum. In practice this
## mostly means not starting a display manager or any other complex daemons
## and not touching the device until the measurement is finished.

# How often the energy consumption should be read, the total duration of the
# measurement is N_RUNS * UPDATE_INTERVAL.
# A value of 30 means we measure the consumption over 15 minutes
N_RUNS=30

# The interval in seconds /sys/class/power_supply/BAT1/energy_now should be read
# This should be set to the platform dependent interval that energy_now gets
# updated in.
UPDATE_INTERVAL=30

OUTFILE_NAME="measurement.txt"

if [ $UID != "0" ]; then
  echo "start me as root"
  exit 1
fi

function exittrap {
  echo "cleaning up"
  umount tmpfs
}

echo "disabling cursor blink"
echo 0 > /sys/class/graphics/fbcon/cursor_blink

echo "setting brightness to 1"
echo 1 > /sys/class/backlight/intel_backlight/brightness

# We store all the values during measuring on a ramdisk to make sure we don't
# wake up the ssd/pcie link all the time (not sure if that's actually working)
echo "creating tmpfs"
mkdir -p tmpfs
mount -t tmpfs -o size=20m recordramdisk tmpfs
trap exittrap EXIT

n=0
accumulated_mWh=0

old_energy=$(cat /sys/class/power_supply/BAT1/energy_now | awk '{ print int($NF/1000) }')

old_pc10=$(cat /sys/kernel/debug/pmc_core/package_cstate_show | grep C10 | awk '{ print int($NF/1000000) }')
old_s0ix=$(cat /sys/kernel/debug/pmc_core/slp_s0_residency_usec | awk '{ print int($NF/1000000) }')

time_now=$(date +%s)
time_finished=$(expr $time_now + $(expr $(expr $N_RUNS + 1) "*" $UPDATE_INTERVAL))
date_finished=$(date -d @$time_finished)

echo "Starting measurement, the results will be written to $OUTFILE_NAME"

echo "We'll finish at $date_finished"

while true; do
  sleep $UPDATE_INTERVAL

  new_energy=$(cat /sys/class/power_supply/BAT1/energy_now | awk '{ print int($NF/1000) }')
  new_pc10=$(cat /sys/kernel/debug/pmc_core/package_cstate_show | grep C10 | awk '{ print int($NF/1000000) }')
  new_s0ix=$(cat /sys/kernel/debug/pmc_core/slp_s0_residency_usec | awk '{ print int($NF/1000000) }')
  new_loadavg=$(cat /proc/loadavg | awk '{print $1;}')

  n_mWh_consumed=$(expr $old_energy - $new_energy)
  percent_pc10=$(expr $(expr $(expr $new_pc10 - $old_pc10) "*" 100) "/" $UPDATE_INTERVAL)
  percent_s0ix=$(expr $(expr $(expr $new_s0ix - $old_s0ix) "*" 100) "/" $UPDATE_INTERVAL)

  old_energy=$new_energy
  old_pc10=$new_pc10
  old_s0ix=$new_s0ix

  n=$(expr $n + 1)

  # We throw the first measurement away since it's very likely to be inaccurate
  if [ "$n" == "1" ]; then
    continue
  fi

  accumulated_mWh=$(expr $accumulated_mWh + $n_mWh_consumed)

  echo "energy consumed(mWh) $n_mWh_consumed : energy consumed total(mWh) $accumulated_mWh : pc10(percent) $percent_pc10 : s0ix(percent) $percent_s0ix : loadaverage last minute $new_loadavg" >> tmpfs/outfile

  if [ "$n" == $(expr $N_RUNS + 1) ]; then
    echo "finished, saving the file"
    mv tmpfs/outfile "$OUTFILE_NAME"
    exit 0
  fi
done

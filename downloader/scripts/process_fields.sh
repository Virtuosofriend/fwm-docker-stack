#!/bin/bash

for field in $SINGLE_LEVEL_FIELDS; do
  echo "Processing: $field"
  
  # Get the current UTC hour
  hour=$(date -u +"%H")
  echo "Current hour: $hour"
  
  # Determine the timestamp based on the hour
  timestamp=$(date -u +"%Y-%m-%d 06:00:00")

  echo "Timestamp: $timestamp"
  
  # Create the directory and clear existing files
  mkdir -p /data/"$field"
  rm -rf /data/"$field"/*
  
  # Run the downloader command with the calculated timestamp
  downloader --model icon-eu --single-level-fields "$field" --min-time-step 0 --max-time-step 48 --timestamp "$timestamp" --directory /data/"$field"
done

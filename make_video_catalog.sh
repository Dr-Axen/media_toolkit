#!/bin/bash
#########################################################
# This script crawls given directory for audio files    #
# and checks their metadata against folder structure.   #
# It is geared towards Audiobooks with Booksonic server #
# but can be modified for other uses.                   #
# It expects the following folder structure:            #
# <start_dir>/<author/artist>[/<series>]/<album/title>/ #
# It outputs a CSV-formatted data.                      #
# Requires "ffprobe"                                    #
#########################################################

# function to get single video file info
vidinfo () {
	if [ -z "$*" ]; then
	  echo Need file name
	  exit
	else 
	  file="$*"
	fi
	# do not show stderr
	exec 2> /dev/null
	# check if the file is a video file
	filetype=$(file -N -i "$file"  | cut -d ':' -f 2,2  | cut -d '/' -f1,1 | awk '{print $1}')
	if [ "$filetype" == "video" ]; then 
	  path=$(dirname "$file")
      name=$(basename "$file")
	  # replace double quotes with double primes (looks similar, avoids CSV problems)
	  filepath=$(echo $path | tr '"' '″')
	  filename=$(echo $name | tr '"' '″')
	  size=$(ls -lah "$file" | awk '{print $5}')
	  size_bytes=$(ls -la "$file" | awk '{print $5}')
	  info=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name,codec_tag_string,width,height,display_aspect_ratio,duration -of csv=s=,:p=0 -sexagesimal "$file")
	  codec_name=$(echo $info | cut -d',' -f 1,1)
	  codec_tag_string=$(echo $info | cut -d',' -f 2,2)
	  width=$(echo $info | cut -d',' -f 3,3)
	  height=$(echo $info | cut -d',' -f 4,4)
	  display_aspect_ratio=$(echo $info | cut -d',' -f 5,5)
	  duration=$(echo $info | cut -d',' -f 6,6)
	  echo '"'$filepath'","'$filename'","'$codec_name'","'$codec_tag_string'","'$width'","'$height'","'$display_aspect_ratio'","'$duration'","'$size'","'$size_bytes'"'
	fi
}

# main program starts here
export -f vidinfo
if [ -z "$*" ]; then
  echo Need directory name
  exit
else 
  start_dir="$*"
fi
# print header
echo '"path","name","codec_name","codec_tag","width","height","aspect_ratio","duration","size","size_bytes"'
# find all directories and check them
find "$start_dir" -type f -exec bash -c 'vidinfo "$0"' "{}" \; 

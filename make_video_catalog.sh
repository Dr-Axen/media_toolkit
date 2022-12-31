#!/bin/bash
############################################################
# This script crawls given directory for video files       #
# and obtains their metadata.                              #
# It is geared towards media servers like Jellyfin         #
# but can be modified for other uses.                      #
# It expects the following folder structure:               #
# <start_dir>/<library/type/collection>[/<other>]/<title>/ #
# It outputs a CSV-formatted data.                         #
# Requires "ffprobe"                                       #
############################################################

# function to get single video file info
vidinfo () {
	if [ -z "$*" ]; then
	  echo Need file name
	  exit
	else 
	  file="$*"
	fi
	# do not show stderr
	#exec 2> /dev/null
	# check if the file is a video file
	filetype=$(file -N -i "$file"  | cut -d ':' -f 2,2  | cut -d '/' -f1,1 | awk '{print $1}')
	if [ "$filetype" == "video" ]; then
	  # get info from the file itself
	  path=$(dirname "$file")
      filepart=$(basename "$file")
	  name="${filepart%.*}"
	  nfo="$path/${name}.nfo"
	  size=$(ls -lah "$file" | awk '{print $5}')
	  size_bytes=$(ls -la "$file" | awk '{print $5}')
	  info=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name,codec_tag_string,width,height,display_aspect_ratio,duration -of csv=s=,:p=0 -sexagesimal "$file")
	  codec_name=$(echo $info | cut -d',' -f 1,1)
	  codec_tag_string=$(echo $info | cut -d',' -f 2,2)
	  width=$(echo $info | cut -d',' -f 3,3)
	  height=$(echo $info | cut -d',' -f 4,4)
	  display_aspect_ratio=$(echo $info | cut -d',' -f 5,5)
	  duration=$(echo $info | cut -d',' -f 6,6)
      # check NFO
	  # replace double quotes with double primes (looks similar, avoids CSV problems)
	  if [[ -r "$nfo" ]]; then
	    title=$(cat "$nfo" | grep -oPm1 "(?<=<title>)[^<]+" | tr '"' '″')
	    originaltitle=$(cat "$nfo" | grep -oPm1 "(?<=<originaltitle>)[^<]+" | tr '"' '″')
	    year=$(cat "$nfo" | grep -oPm1 "(?<=<year>)[^<]+")
	    runtime=$(cat "$nfo" | grep -oPm1 "(?<=<runtime>)[^<]+")
	    imdbid=$(cat "$nfo" | grep -oPm1 "(?<=<imdbid>)[^<]+")
	    tmdbid=$(cat "$nfo" | grep -oPm1 "(?<=<tmdbid>)[^<]+")
	    country=$(cat "$nfo" | grep -oPm1 "(?<=<country>)[^<]+")
	  fi
	  path_normalized=$(echo $path | sed "s#${start_dir}##") 
	  filepath=$(echo $path_normalized | tr '"' '″')
	  filename=$(echo $filepart | tr '"' '″')
      library=$(echo $path_normalized | cut -d '/' -f 1,1)
      movie_folder=${path_normalized##*/}
	  echo '"'$filepath'","'$filename'","'$library'","'$movie_folder'","'$codec_name'","'$codec_tag_string'","'$width'","'$height'","'$display_aspect_ratio'","'$duration'","'$size'","'$size_bytes'","'$title'","'$originaltitle'","'$year'","'$runtime'","'$imdbid'","'$tmdbid'","'$country'"'
	  # do not stress the disk too much
	  sleep 1
	fi
}

# main program starts here
export -f vidinfo
if [ -z "$*" ]; then
  echo Need directory name
  exit
else 
  start="$*"
fi
last_char=${start: -1}
if [[ "$last_char" == "/" ]]; then
  start_dir="$start"
else
  start_dir="${start}/"
fi
export start_dir
# print header
echo '"path","name","library","movie_folder","codec_name","codec_tag","width","height","aspect_ratio","duration","size","size_bytes","title","originaltitle","year","runtime","imdbid","tmdbid","country"'
# find all directories and check them
find "$start_dir" -type f -exec bash -c 'vidinfo "$0"' "{}" \; 

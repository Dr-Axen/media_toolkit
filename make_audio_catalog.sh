#!/bin/bash
#########################################################
# This script crawls given directory for audio files    #
# and checks their metadata against folder structure.   #
# It is geared towards Audiobooks with Booksonic server #
# but can be modified for other uses.                   #
# It expects the following folder structure:            #
# <start_dir>/<author/artist>[/<series>]/<album/title>/ #
# It outputs a CSV-formatted data.                      #
#########################################################

# function to check single folder
check_audio_meta () {
	dir="$1"
	if [ "x$dir" == "x" ]; then
	  echo Need directory name
	  exit
	fi
	# do not show stderr
	exec 2> /dev/null
	# check if the folder has files in it
	has_files=$(find "$dir" -maxdepth 1 \( ! -name 'desc.txt' -and ! -name 'cover.*' \) -type f -printf '.')
	if [[ "x$has_files" != "x" ]]; then
	  # Booksonic expects album cover in "cover.jpg" or "cover.png"
	  has_cover=$(ls -l "$dir" | grep cover. | wc -l)
	  # Booksonic expects album description in "desc.txt"
	  has_desc=$(ls -l "$dir" | grep desc.txt | wc -l)
	  # check if any of the audio files have embedded cover art
	  embedded=$(tone dump "$dir" | grep 'embedded pictures' | wc -l) 
	  if [[ $embedded -gt 0 ]]; then
	    embedded_cover=1
	  else
	    embedded_cover=0
	  fi
	  # parse author, series and title from the directory structure
	  author="$(echo $dir | cut -d '/' -f 5,5)"
	  part1="$(echo $dir | cut -d '/' -f 6,6)"
	  part2="$(echo $dir | cut -d '/' -f 7,7)"
	  part3="$(echo $dir | cut -d '/' -f 8,8)"
	  if [[ "x$part3" != "x" ]]; then
	    series="$part1 - $part2"
	    title="$part3"
	  else 
	    if [[ "x$part2" != "x" ]]; then
	      series="$part1"
	      title="$part2"
	    else
	      series=""
	      title="$part1"
	    fi
	  fi
	  # extract audio metadata and check if the author matches
	  author_matches_meta=1
	  files=$(find "$dir" -maxdepth 1 -type f -exec file "{}" \; | grep -E '\s(Audio|MP4|ASF)' | cut -d ':' -f 1,1)
	  file=$(echo "$files" | head -1)
	  meta_artist=$(ffprobe -loglevel error -show_entries format_tags=artist -of default=noprint_wrappers=1:nokey=1 "$file" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
	  meta_album=$(ffprobe -loglevel error -show_entries format_tags=album -of default=noprint_wrappers=1:nokey=1 "$file" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
	  # comment needs to be sanitized because it may contain double-quotes, so convert them to backticks
	  meta_comment=$(ffprobe -loglevel error -show_entries format_tags=comment -of default=noprint_wrappers=1:nokey=1 "$file" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | tr '"' '`')
	  if [[ "$meta_artist" != "$author" ]]; then
	    author_matches_meta=0
	  fi
	  # output the result as CSV data line
	  echo '"'$dir'","'$author'","'$meta_artist'","'$series'","'$title'","'$meta_album'","'$meta_comment'",'$embedded_cover','$has_desc','$has_cover','$author_matches_meta
	fi
}
# main program starts here
export -f check_audio_meta
start_dir="$1"
if [ "xstart_$dir" == "x" ]; then
  echo Need directory name
  exit
fi
# print header
echo '"path","author","meta_artist","series","title","meta_album","meta_comment","embedded_cover","has_desc","has_cover","author_matches_meta"'
# find all directories and check them
find "$start_dir" -type d -exec bash -c 'check_audio_meta "$0"' "{}" \; 

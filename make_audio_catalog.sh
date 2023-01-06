#!/bin/bash
#########################################################
# This script crawls given directory for audio files    #
# and checks their metadata against folder structure.   #
# It is geared towards Audiobooks with Booksonic server #
# but can be modified for other uses.                   #
# It expects the following folder structure:            #
# <start_dir>/<author/artist>[/<series>]/<album/title>/ #
# It outputs a CSV-formatted data.                      #
# Requires "tone" and "ffprobe"                         #
#########################################################
# return values from functions are opposite of what normal bash/unix 
# exit codes are. They are boolean Yes=1/No=0 instead.
# This seemed more logical.

# function to extract cover image from an audio file
extract_cover() {
	file="$*"
	if [ "x$file" == "x" ]; then
	  return 0
	fi
	codec=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=s=,:p=0 -sexagesimal "$file")
	case "$codec" in 
	  "mjpeg")
	    ext="jpg"
	    ;;
	  "png")
	    ext="png"
	    ;;
	   *)
	    ext="img"
	    return 0
	    ;;
	esac
	ffmpeg -i "$file" -an -c:v copy cover.$ext
	echo "Extracted '"$ext"' image" >&2
    return 1
}

# function to check files for an embedded cover
check_embedded_cover() {
	if [ -z "$*" ]; then
	  return 1
	else 
	  dir="$*"
	fi
	# find all audio files
	file * | grep Audio | head -1 | cut -d ':' -f1,1 | while read -r filename; do
	  has_embedded=$(tone dump "$filename" | grep 'embedded pictures' | wc -l)
	  if [[ $has_embedded -gt 0 ]]; then
	    extract_cover "$filename" 
	    status=$*
	    echo "extract_cover returned $status" >&2
	    if  [[ $status -gt 0 ]]; then 
	      return 1
	    fi
	  fi
	done
	# nothing extracted
	return 0
}

# function to check for a cover image in specific folder
check_cover() {
	if [ -z "$*" ]; then
	  return 0
	else 
	  dir="$*"
	fi
	# Booksonic expects album cover in "cover.jpg" or "cover.png"
	echo "1) Checking for file named 'cover.*'" >&2
	cd "$dir"
	cover="$(find "$dir" -maxdepth 1 -type f -name 'cover.*' -print | head -1)"
	# check if the file is an image
	is_image=$(file "$cover" | grep -w image | wc -l)
	if [[ $is_image -gt 0 ]]; then
	  echo "Cover file exists" >&2
	  return 1
	fi
	# if any of the audio files have embedded cover art, extract it
	echo "2) Checking for embeddd cover" >&2
	check_embedded_cover "$dir"
    status=$*
    echo "check_embedded_cover returned $status" >&2
	# why below does not work? check "$?", perhaps return value is wrong
	if  [[ $? -gt 0 ]]; then 
	  echo "Embedded cover exists" >&2
	  return 1
	fi
	# try to find cover image with a different name
	echo "3) Checking for file named '*[Cc]over*.*'" >&2
	alt_cover=$(ls *[Cc]over* | grep -wi cover | head -1)
	# check if the file is an image
	is_image="$(file "alt_$cover" | grep -w image | wc -l)"
	if [[ $is_image -gt 0 ]]; then
	  echo "Found alernate cover file" >&2
	  # copy the file to cover.<ext>
	  ext="${alt_cover##*.}"
	  cp "$alt_cover" "cover.$ext"
	  return 1
	fi
	# check for any image files
	echo "4) Checking for any images files" >&2
	image=$(find "$dir" -maxdepth 1 -type f \( -name '*.jpg' -o -name '*.png' \) \! -size 0 -print | head -1)
	# hopefully it's a cover image, fingers crossed!
	is_image=$(file "$image" | grep -w image | wc -l)
	if [[ $is_image -gt 0 ]]; then
	  echo "Found image file, fingers crossed" >&2
	  # copy the file to cover.<ext>
	  ext="${image##*.}"
	  cp "$image" "cover.$ext"
	  return 1
	fi
	#not found
	echo "5) Cover not found." >&2
	return 0
}

# function to check single folder
check_audio_meta () {
	if [ -z "$*" ]; then
	  return 0
	else 
	  dir="$*"
	fi
	# check if the folder has files in it, besides just cover and description
	has_files=$(find "$dir" -maxdepth 1 -type f \( ! -name 'desc.txt' -and ! -name 'cover.*' \) \! -size 0 -type f -print | wc -l )
	if [[ $has_files -gt 0 ]]; then
	  echo "---" >&2
	  echo "Analyzing '"$dir"'" >&2
	  # Booksonic expects album cover in "cover.jpg" or "cover.png"
	  check_cover "$dir"
	  has_cover=$?
	  # Booksonic expects album description in "desc.txt"
	  has_desc=$(find "$dir" -maxdepth 1 -type f -name 'desc.txt' \! -size 0 -print | wc -l)
	  # see if there are other text files there
	  has_txt=$(find "$dir" -maxdepth 1 -type f \( -name '*.txt' -o -name '*.nfo' \) \( \! -name 'desc.txt' -a \! -name 'reader.txt' \) \! -size 0 -print | wc -l)	  
	  if [[ $has_txt -gt 0 ]]; then
	    echo "$dir has other text files" >&2
	  fi
	  # Booksonic expects narrator in "reader.txt"
	  has_reader=$(find "$dir" -maxdepth 1 -type f -name 'reader.txt' \! -size 0 -print | wc -l)
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
	  # metadata needs to be sanitized for CSV because it may contain double-quotes, so convert them to double primes
	  author_matches_meta=1
	  files=$(find "$dir" -maxdepth 1 -type f -exec file "{}" \; | grep -E '\s(Audio|MP4|ASF)' | cut -d ':' -f 1,1)
	  file=$(echo "$files" | head -1)
	  meta_artist=$(ffprobe -loglevel error -show_entries format_tags=artist -of default=noprint_wrappers=1:nokey=1 "$file" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | tr '"' '″')
	  meta_album=$(ffprobe -loglevel error -show_entries format_tags=album -of default=noprint_wrappers=1:nokey=1 "$file" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | tr '"' '″')
	  meta_comment=$(ffprobe -loglevel error -show_entries format_tags=comment -of default=noprint_wrappers=1:nokey=1 "$file" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | tr '"' '″')
	  if [[ "$meta_artist" != "$author" ]]; then
	    author_matches_meta=0
	  fi
	  echo "Found '"$dir"' with the following metadata artist='"$meta_artist"', album='"$meta_album"', comment='"$meta_comment"'" >&2
	  echo "Has cover: ["$has_cover"], Has desc: ["$has_desc"], Has reader: ["$has_reader"]" >&2
	  path=$(echo $dir | sed "s%$start_dir%%")
	  # output the result as CSV data line
	  echo '"'$start_dir'","'$path'","'$author'","'$meta_artist'","'$series'","'$title'","'$meta_album'","'$meta_comment'",'$author_matches_meta','$has_cover','$has_desc','$has_reader','$has_txt
	fi
	return 1
}
########################################################################
# main program starts here
########################################################################
export -f check_audio_meta check_cover check_embedded_cover extract_cover
# set initial parameter values
start_dir="."
# read parameters
while getopts ":d:o:" opt; do
  case $opt in
    d)
      start_dir="$OPTARG"
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
    :)
      echo "Option -$OPTARG requires an argument." >&2
      exit 1
      ;;
  esac
done
export start_dir
echo "Starting program in '"$start_dir"'" >&2
# print header
echo '"library folder","path","author","meta_artist","series","title","meta_album","meta_comment","author_matches_meta","has_cover","has_desc","has_reader","has_text"'
# find all directories and check them
find "$start_dir" -type d -exec bash -c 'check_audio_meta "$0"' "{}" \; 

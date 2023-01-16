#!/bin/bash
# check_subtitle_file.sh
# file can be SRT or SUB
# usage:
#  find <start_dir> -type f \( -name '*.srt' -o -name '*.sub' \) -exec check_subtitle_file.sh "{}" \;
#
file="$*"
if [[ "x$file" == "x" ]]; then
  echo "Need file name" >&2
  exit 1
fi
echo "Checking: $file"
filename="${file##*/}"
extension="${filename##*.}"
filebase="${filename%.*}"
filepath="$(dirname "${file}")"
ext=$(echo "$extension" | tr '[:upper:]' '[:lower:]')
if [[ "$ext" == "srt" ]]; then
  # SRT has number in first line, preferably "1" (seq number)
  # If it is "{" or "[" it is most likely SUB file
  # we need to strip UTF BOM if it exists
  firstchar=$(head -1 "$file" | sed "1s/^$(printf '\357\273\277')//" | cut -c 1,1)
  case $firstchar in 
  '{')
    echo -e "\tThis file appears to be a MicroDVD SUB format"
    echo -e "\tRenaming...\c"
    mv "$file" "${filepath}/${filebase}.sub"
    ext="sub"
    filename="${filebase}.${ext}"
    file="{filepath}/${filename}"
    ;;
  '[')
    echo -e "\tThis file appears to be a MicroDVD SUB format with suqare brackets"
    echo -e "\tFixing and renaming..."
    cat "$file" | tr '[' '{' | tr ']' '}' > "${filepath}/${filebase}.sub" && rm "$file" 
    ext="sub"
    filename="${filebase}.${ext}"
    file="{filepath}/${filename}"
    ;;
  '1')
    echo -e "\tThis file appears to be a SRT format"
    echo -e "\tRunning SRT checker..."
	  srt_checker convert "$file"
    ;;
  *)
    echo -e "\tNot sure about this file's format"
    echo "  First char is; ["$(printf "%q\n" $firstchar)"]"
    echo "  First line is: ["$(head -1 "$file")"]"  
    ;;
  esac
fi
if [[ "$ext" == "sub" ]]; then
  # first check if this is VobSub or MicroDVD format
  format=$(file "$file" | sed 's/.*: //')
  is_text=$(echo "$format" | grep -w text | wc -l)
  if [[ $is_text -gt 0 ]]; then
    echo  -e "\tThis file appears to be a MicroDVD SUB format"
    # check if the file structure is correct
    firstline=$(head -1 "$file" | tr -d '\0')
    # the file shoudl have frames in curly brackets, not square ones.
    has_curly=$(echo $firstline | grep -E '^\{' | wc -l)
    if [[ $has_curly -gt 0 ]]; then
      echo  -e "\tThis file has curly brackets"
    else 
      has_square=$(echo $firstline | grep -E '^\[' | wc -l)
      if [[ $has_square -gt 0 ]]; then 
  	    echo -e "\tConverting brackets..."  
   	    mv "$file" "${file}.$$" && cat "${file}.$$" | tr '[' '{' | tr ']' '}' > "$file" && rm "${file}.$$"
      fi
    fi
    # get the first line again (may have been fixed)
    firstline=$(head -1 "$file" | tr -d '\0')        
    # The first line should be a dummy subtitle that has the framerate
    # e.g. {1}{1}25.000
    has_framerate=$(echo "$firstline" | grep -E '^\{[0-9]+\}\{[0-9]+\}[0-9\.]+\s*$' | wc -l)
    if [[ $has_framerate -gt 0 ]]; then
      echo  -e "\tThis file has framerate"
    else 
      echo -e "\tThis file does not seem to have framerate, first line is: $firstline"
      echo -e "\tTrying to get frame rate"
      # get video file with the same name in the same directory
      # sub file can have language in file name
      filebase2="${filebase%.*}"
      vidfile=$(find ${filepath} -maxdepth 1 -type f \( -name "${filebase}.*" -o -name "${filebase2}.*" \) \! -size 0 -type f -exec file -N -i "{}" \; | grep -iw video | cut -d ':' -f 1,1 | head -1)
      if [ "x$vidfile" != "x" ]; then
	      # found video file    
        fr=$(ffprobe -v error -select_streams v -of default=noprint_wrappers=1:nokey=1 -show_entries stream=r_frame_rate "$vidfile")
        if [[ -z $fr ]]; then
          echo -e "\tCould not determine frame rate"
        else 
          frdec=$(($fr))
          echo -e "\tFrame rate is $frdec"
          mv "$file" "${file}.$$" && echo "{1}{1}$frdec" > "$file" && cat "${file}.$$" >> "$file" && rm "${file}.$$"
        fi
      fi
    fi
    echo -e "\tChecking if SRT version already exists... \c"
    srtfile="${filepath}/${filebase}.srt"
    if [[ -r "$srtfile" ]]; then
      echo -e "\tSRT file already exists"
    else 
      echo -e "\tSRT file does not exist, converting"
      ffmpeg -i "$file" "${filepath}/${filebase}.srt" > /dev/null 2>&1
      if [[ $? -eq 0 ]]; then
        echo -e "\tConversion successful"
      else
        echo -e "\tError converting to SRT"
      fi    
    fi
  else
    is_vobsub=$(echo "$format" | grep -E '(MPEG|image)\W' | wc -l)
    if [[ $is_vobsub -gt 0 ]]; then
      echo -e "\tThis file appears to be a VobSub SUB format"
      # check if corresponding IDX file exists
      if [ -s "${filepath}/${filebase}.idx" ]; then
        echo -e "\tIDX file exists"
      else
        # check if any IDX files exists, maybe named differently
        idx=$(ls "${filepath}/*.idx")   
        if [[ "x$idx" == "x" ]]; then
          echo -e "\tOther IDX files exist: $idx"
        else  
          echo -e "\tNo IDX file!"
        fi
      fi
    else 
      echo -e "\tUnrecognized file format: [$format]"
      exit
    fi
  fi
fi
echo "Done."

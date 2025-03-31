#!/bin/sh
set -euo pipefail

#-
# SPDX-License-Identifier: BSD-2-Clause
#
# Copyright (c) 2023-2025 Alexey Laurentsyeu
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.
#-

# Defaults, set to that value if yet unset
corru_audio_fmt="alaw"
corru_audio_rate="44100"
ffmpeg_pix_fmt="yuv420p"
ffmpeg_output_codec="libx264"
ffmpeg_output_crf="0" # Lossless output for these crispy pixels

# Code and things start here!

error()
{
	printf 'Error ==> %s\n' "$@" 1>&2
	exit 1
}

helpmsg()
{
	cat << EOL
--- video-corruptor.sh ---
usage: $0 -i [input] -o [output] ... -f [ffmpeg args]

args:
-i 		Input video file
-o 		Output video file
-f		Start of FFmpeg arguments
-p 		Intermediate raw video pixel format
-r 		Intermediate raw audio rate
-a 		Intermediate raw audio format
-c 		Output file CRF
-m		Let FFmpeg detect output format (useful for images)
-h 		Show this message
EOL
	exit 1
}

if [ -z "$*" ]; then
	helpmsg
fi

f_set=0
m_set=0
argnum=1
for arg in "$@"; do
	argnum=$((argnum+1))
	case "$arg" in
	-i) eval input_file="\$$argnum" ;;
	-o) eval output_file="\$$argnum" ;;
	-f) shift $((argnum-1)) ; f_set=1; break ;;
	-p) eval ffmpeg_pix_fmt="\$$argnum" ;;
	-r) eval corru_audio_rate="\$$argnum" ;;
	-a) eval corru_audio_fmt="\$$argnum" ;;
	-c) eval ffmpeg_output_crf="\$$argnum" ;;
	-m) m_set=1 ;;
	-h) helpmsg ;;
	*) : ;;
	esac
done

# checks

if ! command -v ffmpeg >/dev/null 2>&1; then
	error "FFmpeg not found"
fi

if [ -z "${input_file:-}" ]; then
	error "Missing input file"
elif [ -z "${output_file:-}" ]; then
	error "Missing output file"
elif [ ! -e "$input_file" ] || [ -d "$input_file" ]; then
	error "Invalid input file: $input_file"
elif ! ( touch "$output_file" && rm "$output_file" ) >/dev/null 2>&1; then
	error "Cannot write to $output_file"
elif [ "$f_set" -eq 0 ] || [ -z "${*:-}" ]; then
	error \
		"No FFmpeg filter pipeline after '-f', please add one" \
		"Example: -f -af acrusher=bits=16:samples=64:mix=0.1,aexciter" \
		"https://ffmpeg.org/ffmpeg-filters.html"
fi

video_dimensions="$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$input_file")"
# Die carrying FFmpeg's exit code if it errors out from the input file
if [ "$?" != 0 ]; then
	exit "$?"
fi
video_framerate="$(ffprobe -v error -select_streams v:0 -show_entries stream=avg_frame_rate -of csv=s=x:p=0 "$input_file")"
if [ "$?" != 0 ]; then
	exit "$?"
fi

ffmpeg \
	-y \
	-i "$input_file" \
	-c:v rawvideo \
	-pix_fmt "$ffmpeg_pix_fmt" \
	-f rawvideo \
	pipe: \
| ffmpeg \
	-y \
	-f "$corru_audio_fmt" \
	-ar "$corru_audio_rate" \
	-i pipe: \
	"$@" `: corruption args` \
	-f "$corru_audio_fmt" \
	pipe: \
| if [ "$m_set" -eq 0 ]; then
	ffmpeg \
		-y \
		-f rawvideo \
		-r "$video_framerate" \
		-video_size "$video_dimensions" \
		-pix_fmt "$ffmpeg_pix_fmt" \
		-i pipe: \
		-c:v "$ffmpeg_output_codec" \
		-crf "$ffmpeg_output_crf" \
		"$output_file" || exit "$?"
  else
	ffmpeg \
		-y \
		-f rawvideo \
		-r "$video_framerate" \
		-video_size "$video_dimensions" \
		-pix_fmt "$ffmpeg_pix_fmt" \
		-i pipe: \
		-c:v png \
		"$output_file" || exit "$?"
  fi

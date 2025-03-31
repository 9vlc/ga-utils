#!/bin/sh

vc="$PWD/video-corruptor.sh"
tmp="$(mktemp -d)"

if [ -z "$1" ] || [ -z "$2" ]; then
	echo "usage: $0 input.png output.png"
	exit 1
fi

$vc -m -i "$1" -o "$tmp/1.png" -p monob -f -af anull
$vc -m -i "$tmp/1.png" -o "$tmp/2.png" -p yuv420p -f -filter_complex "aevalsrc=0.1*random(0):d=6[a];[0:a][a]amix=inputs=2"
$vc -m -i "$tmp/2.png" -o "$2" -p yuv420p -f -af acrusher=bits=32:samples=4:mix=0.6,lowpass=f=2000

echo "$tmp"
#rm -r "$tmp"

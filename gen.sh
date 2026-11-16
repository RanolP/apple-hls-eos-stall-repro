#!/bin/sh
# Generates the bundled HLS VOD under ./Media/content:
#   video/  DURATION (default 300) s H.264 test pattern 320x180, 6 s TS segments (no audio)
#   audio/  DURATION s AAC sine, 6 s TS segments (separate AUDIO rendition)
#   subs/   ONE WebVTT segment, EXTINF SUBDUR (default 280) s (shorter than the media)
#   master.m3u8 with AUDIO group "aud" and SUBTITLES group "text" (AUTOSELECT=YES)
set -eu
cd "$(dirname "$0")"
out=Media/content
rm -rf "$out"
mkdir -p "$out/video" "$out/audio" "$out/subs"

ffmpeg -hide_banner -loglevel error -f lavfi -i testsrc2=size=320x180:rate=30 -t ${DURATION:-300} \
  -c:v libx264 -profile:v main -pix_fmt yuv420p -b:v 120k -maxrate 160k -bufsize 320k \
  -force_key_frames 'expr:gte(t,n_forced*6)' -an \
  -f hls -hls_time 6 -hls_playlist_type vod -hls_segment_type mpegts \
  -hls_segment_filename "$out/video/v%03d.ts" "$out/video/index.m3u8"

ffmpeg -hide_banner -loglevel error -f lavfi -i sine=frequency=440:sample_rate=48000 -t ${DURATION:-300} \
  -c:a aac -b:a 32k -ac 2 \
  -f hls -hls_time 6 -hls_playlist_type vod -hls_segment_type mpegts \
  -hls_segment_filename "$out/audio/a%03d.ts" "$out/audio/index.m3u8"

cat > "$out/subs/sub0.vtt" <<'EOF'
WEBVTT
X-TIMESTAMP-MAP=MPEGTS:126000,LOCAL:00:00:00.000

00:00:01.000 --> 00:00:04.000
Cue one

00:00:10.000 --> 00:00:14.000
Cue two

00:00:30.000 --> 00:00:34.000
Cue three

00:00:45.000 --> 00:00:49.000
Cue four
EOF

cat > "$out/subs/index.m3u8" <<EOF
#EXTM3U
#EXT-X-VERSION:3
#EXT-X-TARGETDURATION:${SUBDUR:-280}
#EXT-X-MEDIA-SEQUENCE:0
#EXT-X-PLAYLIST-TYPE:VOD
#EXTINF:${SUBDUR:-280}.000,
sub0.vtt
#EXT-X-ENDLIST
EOF

cat > "$out/master.m3u8" <<'EOF'
#EXTM3U
#EXT-X-VERSION:4
#EXT-X-INDEPENDENT-SEGMENTS
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud",LANGUAGE="en",NAME="Audio",DEFAULT=YES,AUTOSELECT=YES,CHANNELS="2",URI="audio/index.m3u8"
#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="text",LANGUAGE="en",NAME="English",DEFAULT=NO,AUTOSELECT=YES,FORCED=NO,URI="subs/index.m3u8"
#EXT-X-STREAM-INF:BANDWIDTH=250000,AVERAGE-BANDWIDTH=180000,CODECS="avc1.4d400d,mp4a.40.2",RESOLUTION=320x180,FRAME-RATE=30.000,AUDIO="aud",SUBTITLES="text"
video/index.m3u8
EOF

echo "generated: $(pwd)/$out"

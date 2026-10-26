Synthetic one-second media fixtures for #128; no recorded speech or personal data.

Generated using ffmpeg:

```
ffmpeg -f lavfi -i color=c=black:s=16x16:r=2:d=1 -f lavfi -i sine=frequency=440:sample_rate=48000:duration=1 -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest import-tone.mp4
ffmpeg -i import-tone.mp4 -c copy import-tone.mov
ffmpeg -i import-tone.mp4 -an -c:v copy import-silent.mp4
```

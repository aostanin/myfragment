# Kinect Framegrabber

Grabs depth frames from Kinect and outputs them to a named pipe.

## Examples

### Use ffmpeg to create a video

    ffmpeg -y -f rawvideo -vcodec rawvideo -s 640x480 -pix_fmt gray16le -r 30 -i kinect.fifo -vf "lutrgb='r=6.5535*val:g=6.5535*val:b=6.5535*val',boxblur='luma_radius=5:luma_power=3'" -an -vcodec h264 -preset fast -tune fastdecode depth.mp4

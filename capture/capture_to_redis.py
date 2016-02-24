import os
import socket
import io
import struct
import time
import picamera
import redis
import base64

# Start the picam
with picamera.PiCamera() as camera:
    try:
        camera.resolution = (480, 360)
        camera.framerate = 10
        # Start a preview and let the camera warm up for 2 seconds
        camera.start_preview()
        time.sleep(2)
        camera.shutter_speed = 0

        # Capture continuously in BytesIO in video mode
        stream = io.BytesIO()
        r = redis.StrictRedis(host='127.0.0.1', port='6379')
        r.set('new_image', 'false')

        for foo in camera.capture_continuous(stream, 'jpeg', use_video_port=True):
            # Write the length of the capture to the stream and flush to
            # ensure it actually gets sent

            if r.get('new_image') == b'false':
                image_size = stream.tell()
                r.set('image_size', image_size)
                # Rewind the stream and send the image data over the wire
                stream.seek(0)
                print('Sending image with size: %d' %image_size + ' to nginx')
                image_data = stream.read()
                r.set('image_data', base64.b64encode(image_data))
                print('Image sent to redis! Take another')
                r.set('new_image', 'true')

            # Reset the stream for the next capture
            stream.seek(0)
            stream.truncate()

#    except KeyboardInterrupt as e:
#        break

    finally:
        print('Stopping capture')
        camera.close()



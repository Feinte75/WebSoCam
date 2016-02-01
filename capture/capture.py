import io
import socket
import struct
import time
import picamera
import os

# Create Unix socket and bind it to file
server_socket = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
if os.path.exists("/var/run/capture.sock"):
    os.remove("/var/run/capture.sock")

server_socket.bind('/var/run/capture.sock')

# Nginx worker is spawned as user "nobody"
# Necessary to change owner for lua code access
os.system("chown nobody /var/run/capture.sock")
server_socket.listen(1)

# Make a file-like object out of the first incoming connection
connection = server_socket.accept()[0].makefile('wb')

print("Got a client ! ")
try:
    # Start the picam
    with picamera.PiCamera() as camera:
        camera.resolution = (480, 360)
        camera.framerate = 10
        # Start a preview and let the camera warm up for 2 seconds
        camera.start_preview()
        time.sleep(2)
        camera.shutter_speed = 0

        # Capture continuously in BytesIO
        stream = io.BytesIO()
        for foo in camera.capture_continuous(stream, 'jpeg', use_video_port=True):
            # Write the length of the capture to the stream and flush to
            # ensure it actually gets sent
            connection.write(struct.pack('<L', stream.tell()))
            connection.flush()
            # Rewind the stream and send the image data over the wire
            stream.seek(0)
            print('Sending image to nginx')
            connection.write(stream.read())
            print('Image sent ! Take another')
            # Reset the stream for the next capture
            stream.seek(0)
            stream.truncate()

    # Write a length of zero to the stream to signal we're done
    connection.write(struct.pack('<L', 0))
finally:
    connection.close()
    server_socket.close()
    os.remove("/var/run/capture.sock")

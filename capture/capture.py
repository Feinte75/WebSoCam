import os
import socket
import io
import struct
import time
import picamera

if os.path.exists("/var/run/capture.sock"):
    os.remove("/var/run/capture.sock")

# Create Unix socket and bind it to file
server_socket = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
server_socket.bind('/var/run/capture.sock')

# Nginx worker is spawned as user "nobody"
# Necessary to change socket owner for lua code access
os.system("chown nobody /var/run/capture.sock")
server_socket.listen(1)

# Make a file-like object out of the first incoming connection
while True :
    nginx_connection = server_socket.accept()[0].makefile('wb')

    print("Got a client ! ")
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

            for foo in camera.capture_continuous(stream, 'jpeg', use_video_port=True):
                # Write the length of the capture to the stream and flush to
                # ensure it actually gets sent
                image_length = stream.tell()
                nginx_connection.write(struct.pack('<L', image_length))
                nginx_connection.flush()
                # Rewind the stream and send the image data over the wire
                stream.seek(0)
                print('Sending image with length: %d' %image_length + ' to nginx')
                nginx_connection.write(stream.read())
                print('Image sent ! Take another')
                # Reset the stream for the next capture
                stream.seek(0)
                stream.truncate()

        except KeyboardInterrupt as e:
            nginx_connection.write(struct.pack('<L', 0))
            print('Stopping capture')
            break

        except socket.error as (value,message) :
            print('Socket error occured : ' + message )
            print('Capture ended, wait for another client')

        finally:
            camera.close()

nginx_connection.close()
server_socket.close()
os.remove("/var/run/capture.sock")

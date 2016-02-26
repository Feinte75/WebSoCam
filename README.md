Raspicam MJpeg streaming with Websocket, Redis and OpenResty

Continuous image capture is done with a Python script, jpeg images are sent to Redis

On websocket client connect, a lua script recover the images from Redis and send them continuously to the client

Client side images are recovered and embedded in an image tag as base64

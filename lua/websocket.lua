local server = require "resty.websocket.server"
local redis  = require "resty.redis"

-- Create web socket
local wb, err = server:new
{
  timeout = 1000,  -- in milliseconds
  max_payload_len = 1000000,
}

if not wb then
  ngx.log(ngx.ERR, "Failed to new websocket: ", err)
  return ngx.exit(444)
end

-- Receive connecting frame from client
local data, typ, err = wb:recv_frame()

if not data then
  ngx.log(ngx.ERR, "Failed to receive a frame: ", err)
  return ngx.exit(444)
end

ngx.log(ngx.INFO, "Received a frame of type ", typ, " and payload ", data)

-- Create redis client and connect to redis server
local r = redis:new()
r:set_timeout(1000)

local ok, err = r:connect("127.0.0.1", 6379)

if not ok then
  ngx.log(ngx.ERR, "Failed to connect to redis: ", err)
  return ngx.exit(444)
end

ngx.log(ngx.INFO, "Connected to Redis !")

-- Loop : Get image from redis and send it to client
-- loop parameters :
local done = false
local timeout = 0
local wait_time = 0.002

--ok, err = r:set("new_image", "false")
--if not ok then
--  ngx.log(ngx.ERR, "Tried to set new_image boolean and got err : ", err)
--  return ngx.exit(444)
--end

repeat

  -- TODO Implement some kind of ping pong messages
  --  local data, typ, err = wb:recv_frame()

--  if typ == "close" then
    -- Client asked to stop
--    ngx.log(ngx.ERR, "closing with status code ", err, " and message ", data)
--    break
--  end

  timeout = 0
  -- Check if image has changed since last get
  repeat
    ngx.log(ngx.INFO, "Waiting for new image since: ", timeout)

    ngx.sleep(wait_time)
    timeout = timeout + wait_time

    -- Check if a new image is available in Redis
    local new_image, err = r:get("new_image") 

    if not new_image then 
      ngx.log(ngx.ERR, "Failed to recover new_image")
      break
    end

    if new_image == ngx.null then
      ngx.log(ngx.INFO, "new_image boolean not found")
    end
  until timeout >= 5 or new_image == 'true' 

  -- Exit if no new image in redis for 5 seconds
  if timeout >= 5 then
    ngx.log(ngx.ERR, "Waited for new image in redis for 5 seconds, exiting now")
    break
  end

  ngx.log(ngx.INFO, "Got a new image")

  -- Get image size for logging purposes
  local image_size, err = r:get('image_size')

  if not image_size then
    ngx.log(ngx.ERR, "Couldn't get image_size from redis, err : ",err)
    break
  end

  if image_size == 0 then
    ngx.log(ngx.ERR, "Received 0 length image, stop now")
    break
  end

  -- Get b64 encoded image data from redis
  local image_data, err = r:get("image_data")

  if not image_data then
    ngx.log(ngx.ERR, "Couldn't get image_data from redis, err : ", err)
    break
  end
 
  -- Send base64 encoded jpeg data via the websocket to the client
  local bytes, err = wb:send_binary(image_data)
  if not bytes then
    ngx.log(ngx.ERR, "Failed to send a binary frame: ", err)
    break
  end

  ngx.log(ngx.INFO, "image sent to client")

  -- Inform capture that we can process a new image
  r:set('new_image', 'false')
  new_image = 'false'

until done

-- End communication
local bytes, err = wb:send_close(1000, "Goodbye !")
if not bytes then
  ngx.log(ngx.ERR, "Failed to send the closing frame : ", err)
  return
end


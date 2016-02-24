local server = require "resty.websocket.server"
local struct = require "struct"
local redis  = require "resty.redis"

-- Create web socket
local wb, err = server:new
{
  timeout = 5000,  -- in milliseconds
  max_payload_len = 1000000,
}

if not wb then
  ngx.log(ngx.ERR, "failed to new websocket: ", err)
  return ngx.exit(444)
end

-- Receive frame from client
local data, typ, err = wb:recv_frame()

if not data then
  ngx.log(ngx.ERR, "failed to receive a frame: ", err)
  return ngx.exit(444)
end

ngx.log(ngx.INFO, "received a frame of type ", typ, " and payload ", data)

-- Create redis client
local r = redis:new()
r:set_timeout(1000)

local ok, err = r:connect("127.0.0.1", 6379)

if not ok then
  ngx.log(ngx.ERR, "Failed to connect to redis: ", err)
  return
end

ngx.log(ngx.INFO, "Connected to Redis !")

local done = false
local timeout = 0
local max_increment = 0.002
-- Loop : Get image from redis and send it to client

ok, err = r:set("new_image", "false")
ngx.log(ngx.INFO, "Tryed to set new_image : ok : ", ok, "  err : ", err)
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
    ngx.log(ngx.INFO, "Waiting for image since: ", timeout)
    ngx.sleep(max_increment)
    timeout = timeout + max_increment
    local new_image, err = r:get("new_image") 
    if not new_image then 
      ngx.log(ngx.INFO, "Failed to recover new_image")
      return
    end
    if new_image == ngx.null then
      ngx.log(ngx.INFO, "new_image not found")
    end

    ngx.log(ngx.INFO, "Got ", new_image, " and err ", err )
  until timeout >= 5 or new_image == 'true' 

  if timeout >= 5 then
    ngx.log(ngx.ERR, "Waited for new image in redis for 5 seconds, exiting now")
    break
  end

  ngx.log(ngx.INFO, "Got a new image ! ")
  -- Get image size from socket, the call to receive is blocking
  -- TODO 4 bytes fixed size assumed integer is not a good idea
  -- if capture server != nginx server || on other platform than armv6
  local image_size, err = r:get('image_size')
  ngx.log(ngx.INFO, "Received ", image_size, " long image")
  if image_size == 0 then
    ngx.log(ngx.ERR, "Received 0 length image, stop now")
    break
  end

  -- Read image size bytes from socket
  local image = r:get("image_data")

  -- Send base64 encoded jpeg data via the websocket to the client
  -- bytes, err = wb:send_binary(ngx.encode_base64(image))
  bytes, err = wb:send_binary(image)
  if not bytes then
    ngx.log(ngx.ERR, "Failed to send a binary frame: ", err)
    break;
  end
  ngx.log(ngx.INFO, "image sent to client")
  r:set('new_image', 'false')
  new_image = 'false'

until done

local bytes, err = wb:send_close(1000, "Goodbye !")
if not bytes then
  ngx.log(ngx.ERR, "failed to send the close frame: ", err)
  return
end


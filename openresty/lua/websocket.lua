local server = require "resty.websocket.server"
local struct = require "struct"

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

local done = false
local capture_socket = ngx.socket.tcp()
capture_socket:settimeout(5000)

-- Connect to unix socket
local ok, err = capture_socket:connect("unix:/var/run/capture.sock")
if not ok then
  ngx.say("failed to connect to the image capture unix domain socket: ", err)
  return
end

-- Loop : Receive image from capture script and send it to client
-- TODO Add proper way to exit, it currently exits only when capture script exits
-- Should terminate when web client stop
repeat

  -- TODO Implement some kind of ping pong messages
  --  local data, typ, err = wb:recv_frame()

--  if typ == "close" then
    -- Client asked to stop
--    ngx.log(ngx.ERR, "closing with status code ", err, " and message ", data)
--    break
--  end

  -- Get image size from socket, the call to receive is blocking
  -- TODO 4 bytes fixed size assumed integer is not a good idea
  -- if capture server != nginx server || on other platform than armv6
  local image_size = struct.unpack('<L', capture_socket:receive(4))
  ngx.log(ngx.INFO, "received " .. image_size .. " long image")
  if image_size == 0 then
    ngx.log(ngx.INFO, "received 0 length image, stop now")
    break
  end

  -- Read image size bytes from socket
  local image = capture_socket:receive(image_size)

  -- Send base64 encoded jpeg data via the websocket to the client
  bytes, err = wb:send_binary(ngx.encode_base64(image))
  if not bytes then
    ngx.log(ngx.ERR, "failed to send a binary frame: ", err)
    break;
  end
  ngx.log(ngx.INFO, "image sent to client")

until done

capture_socket:close();
local bytes, err = wb:send_close(1000, "Goodbye !")
if not bytes then
  ngx.log(ngx.ERR, "failed to send the close frame: ", err)
  return
end


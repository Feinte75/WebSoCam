var wsUri = "ws://192.168.1.12/lua";
var output;
var webcam;
var streamControl;
var imageCounter;
var i = 0;

function init()
{
  output = document.getElementById("output");
  webcam = document.getElementById("webcam");
  streamControl = document.getElementById("stream-control");
  imageCounter = document.getElementById("image-counter");

  streamControl.addEventListener("click", startStreaming);
}

function startStreaming()
{
  console.log("Start websocket");
  websocket = new WebSocket(wsUri);
  
  websocket.onopen = function(evt) { onOpen(evt) };
  websocket.onclose = function(evt) { onClose(evt) };
  websocket.onmessage = function(evt) { onMessage(evt) };
  websocket.onerror = function(evt) { onError(evt) };
}

function onOpen(evt)
{
  writeToScreen("CONNECTED");
  // Just send a message, anything, it'll start server streaming images
  doSend("start", "Start streaming !");
}

function onClose(evt)
{
  writeToScreen("DISCONNECTED");
}

// On server message, read image data as binary and inline it in img tag
function onMessage(evt)
{
  var reader = new FileReader();
  reader.addEventListener("loadend", function() {
    webcam.src = "data:image/jpeg;base64," + reader.result;
    incrementImageCounter();
    console.log('Image nb : ' + i + ' loaded');
  });
  reader.readAsBinaryString(evt.data);
}

function incrementImageCounter() {
  i = i + 1;
  imageCounter.innerHTML = "Nb image received : " + i;
}

function onError(evt)
{
  writeToScreen('<span style="color: red;">ERROR:</span> ' + evt.data);
}

function doSend(type, message)
{
  writeToScreen("SEND type : " + type + " with message : " + message);
  msg = {
    type: type,
    text: message,
  }
  websocket.send(JSON.stringify(msg));
}

function writeToScreen(message)
{
  var pre = document.createElement("p");
  pre.style.wordWrap = "break-word";
  pre.innerHTML = message;
  output.appendChild(pre);
}

window.addEventListener("load", init, false);

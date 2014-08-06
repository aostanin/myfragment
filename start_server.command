#! /bin/bash

cd "$(dirname "${BASH_SOURCE[0]}")"

./kinect-framegrabber/build/kinect-framegrabber -f kinect.fifo &
FRAMEGRABBER_PID=$!

./kinect-websocket/kinect-websocket --fifo kinect.fifo -p 9000 -l 0.0.0.0 &
WEBSOCKET_PID=$!

function cleanup {
  echo Cleaning up...
  kill $FRAMEGRABBER_PID
  kill $WEBSOCKET_PID
  exit
}

trap cleanup SIGHUP SIGINT SIGTERM

wait $FRAMEGRABBER_PID
wait $WEBSOCKET_PID

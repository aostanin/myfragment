#! /bin/bash

cd "$(dirname "${BASH_SOURCE[0]}")"

export KINECT_FIFO="$(pwd)/kinect.fifo"

./kinect-framegrabber/build/kinect-framegrabber -b -f "$KINECT_FIFO" &
FRAMEGRABBER_PID=$!

sleep 3

pushd server
go run main.go &
SERVER_PID=$!
popd

function cleanup {
  echo Cleaning up...
  kill $FRAMEGRABBER_PID
  kill $SERVER_PID
  exit
}

trap cleanup SIGHUP SIGINT SIGTERM

sleep 3
open "http://localhost:3000/live"

wait $FRAMEGRABBER_PID
wait $SERVER_PID

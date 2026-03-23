#!/bin/bash

outputFile="./server.jar"
if [ $# -eq 1 ]; then
  outputFile=$1
fi

wget -O $outputFile $(curl -L https://gist.githubusercontent.com/cliffano/77a982a7503669c3e1acb0a0cf6127e9/raw/ 2> /dev/null | head -n 3 | tail -1 | cut -d "|" -f 3)
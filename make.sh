#!/bin/sh

#
# Script designed to be run for development purposes only.
#

"${SUEXEC:-doas}" make LITTLEJET_VERSION=`make -V LITTLEJET_VERSION`+`git rev-parse HEAD`

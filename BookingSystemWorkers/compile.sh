#!/bin/sh
cd /app
#apk add upx
npm install
npm install -g pkg
pkg --loglevel info -t node18-linuxstatic -o ./$2 ./$1
#upx --best -k $2
#rm $2.~
mkdir build && mv $2 build
cd build && tar zcf build.tar.gz * && mv build.tar.gz ../ && cd /app && rm -rf build
exit

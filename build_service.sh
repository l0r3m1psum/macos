#!/bin/sh

# https://relentlesscoding.com/posts/create-macos-app-bundle-from-script/

set -e

mkdir -p build

plutil Info.plist
clang -g -framework AppKit services.m -o build/services

rm -rf build/services.service
mkdir -p build/services.service/Contents/
mkdir -p build/services.service/Contents/MacOS
cp -f Info.plist build/services.service/Contents
cp -f build/services build/services.service/Contents/MacOS

/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f build/services.service

#!/bin/sh

# https://relentlesscoding.com/posts/create-macos-app-bundle-from-script/

set -e

plutil Info.plist
clang -g -framework AppKit services.m -o build/services

mkdir -p build
rm -rf build/services.app
mkdir -p build/services.app/Contents/
mkdir -p build/services.app/Contents/MacOS
cp -f Info.plist build/services.app/Contents
cp -f build/services build/services.app/Contents/MacOS

/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f build/services.app

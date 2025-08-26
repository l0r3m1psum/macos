#!/bin/sh

# TODO: disable only warnings coming from OpenGL

clang -g -Wno-deprecated-declarations \
	-framework Cocoa \
	-framework CoreVideo \
	-framework OpenGL \
	-framework QuartzCore \
	open_window_objc.m -o window

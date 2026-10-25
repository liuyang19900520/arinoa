#!/bin/zsh
# Builds the preview tool against the app's sources, then runs it: ./run.sh input outdir [filter indices...]
set -e
DIR=${0:A:h}; SRC=$DIR/../../BeautyCam; BUILD=$DIR/.build
mkdir -p $BUILD "$2"
xcrun -sdk macosx metal -fcikernel -c $SRC/Beauty.ci.metal -o $BUILD/beauty.air 2>/dev/null
xcrun -sdk macosx metallib -cikernel $BUILD/beauty.air -o $BUILD/default.metallib 2>/dev/null
swiftc -O -o $BUILD/preview $DIR/main.swift $SRC/BeautyEngine.swift $SRC/Styles.swift
cd $BUILD && ./preview "$@"

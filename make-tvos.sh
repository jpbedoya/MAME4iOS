#!/bin/sh
make tvOS=1 clean
make tvOS=1 -j`sysctl -n hw.logicalcpu` CDBG=-w OSVERSION=12.4
open xcode/MAME4iOS/MAME4iOS.xcodeproj/

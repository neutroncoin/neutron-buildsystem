#!/bin/bash
#
# This file is part of The Neutron Build System.
#
# Copyright (c) 2017-2018 The Swipp developers
# Copyright (c) 2019 The Neutron developers
#
# The Neutron Build System is free software: you can redistribute it and/or
# modify it under the terms of the GNU General Public License as published
# by the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# The Neutron Build System is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with The Neutron Build System. If not, see
# <https://www.gnu.org/licenses/>.
#
# Recipe for creating a Neutron QT AppImage package
#
# $1: Location of Neutron executable
# $2: Executable name

if [[ $# -lt 2 ]]; then
	echo "Please specify the full location of the neutron executable and executable name"
	exit 0
fi

if [ -f "$2-x86_64.AppImage" ]; then
	exit 0
fi

# Create AppDir FHS-like stucture
mkdir -p $2.AppDir/usr $2.AppDir/usr/bin

# Used by AppImageKit-checkrt (see below)
mkdir -p $2.AppDir/usr/optional $2.AppDir/usr/optional/libstdc++

# Copy files into empty AppDir
cp $1/$2 $2.AppDir/usr/bin

# Get and run linuxdeployqt
wget --quiet -c https://github.com/probonopd/linuxdeployqt/releases/download/continuous/linuxdeployqt-continuous-x86_64.AppImage
chmod a+x linuxdeployqt-continuous-x86_64.AppImage

# Prepare AppDir
./linuxdeployqt-continuous-x86_64.AppImage --appimage-extract
./squashfs-root/usr/bin/linuxdeployqt $2.AppDir/usr/bin/$2 -bundle-non-qt-libs

# Workaround to increase compatibility with older systems; see https://github.com/darealshinji/AppImageKit-checkrt for details
rm $2.AppDir/AppRun
cp /usr/lib/x86_64-linux-gnu/libstdc++.so.6 $2.AppDir/usr/optional/libstdc++/
wget -quiet -c https://github.com/darealshinji/AppImageKit-checkrt/releases/download/continuous/exec-x86_64.so -O $2.AppDir/usr/optional/exec.so
wget -quiet -c https://github.com/darealshinji/AppImageKit-checkrt/releases/download/continuous/AppRun-patched-x86_64 -O $2.AppDir/AppRun
chmod a+x $2.AppDir/AppRun

# Copy in desktop descriptor and icon
printf "[Desktop Entry]\nType=Application\nName=neutron-qt\nGenericName=neutron-qt\nComment=Store and transfer Neutron coins\nIcon=neutron\nExec=../usr/bin/$2\nTerminal=false\nCategories=Network;Finance;" > $2.AppDir/neutron-qt.desktop
cp neutron/src/qt/res/icons/neutron.png $2.AppDir/

# Manually invoke appimagetool so that the modified AppRun stays intact
PATH=$(readlink -f ./squashfs-root/usr/bin):$PATH
./squashfs-root/usr/bin/appimagetool $2.AppDir $2-x86_64.AppImage

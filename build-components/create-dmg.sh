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
# Small script to create MacOS X DMG archives

# Improve Info.plist
if grep -v -q LSMinimumSystemVersion "$1/Neutron-qt.app/Contents/Info.plist"; then
	tmpfile=$(mktemp)
	head -n -2 $1/Neutron-qt.app/Contents/Info.plist > $tmpfile
	echo -e "\t<key>LSMinimumSystemVersion</key>" >> $tmpfile
	echo -e "\t<string>10.11</string>" >> $tmpfile
	echo -e "\t<key>NSPrincipalClass</key>" >> $tmpfile
	echo -e "\t<string>NSApplication<string>" >> $tmpfile
	echo -e "\t<key>NSSupportAutomaticGraphicsSwitching</key>" >> $tmpfile
	echo -e "\t<true/>" >> $tmpfile
	echo "</dict>" >> $tmpfile
	echo "</plist>" >> $tmpfile
	mv $tmpfile $1/Neutron-qt.app/Contents/Info.plist
fi

# Copy background image
mkdir $1/.background &> /dev/null
cp $1/../neutron/contrib/macdeploy/background.png $1/.background/ &> /dev/null

# Create volume icon
cp $1/Neutron-qt.app/Contents/Resources/neutron.icns $1/.VolumeIcon.icns &> /dev/null

# Do not log file system events
mkdir $1/.fseventsd &> /dev/null
touch $1/.fseventsd/no_log &> /dev/null

# 1312 instead of 1024 bytes. Seems some space needs to be reserved.
# In the end it does not matter much, as the file is compressed.
#dd if=/dev/zero of=$2.dmg bs=1312 count=$(du  -s $1 | cut -f1)
#/sbin/mkfs.hfsplus -v "Neutron Wallet Installer" $2.dmg
#hfsplus $2.dmg addall $1
#hfsplus $2.dmg symlink Applications /Applications

genisoimage -D -V "Neutron Wallet Installer" -allow-leading-dots -no-pad -r -apple -o $2.dmg $1
dmg dmg $2.dmg $2-compressed.dmg
mv -f $2-compressed.dmg $2.dmg

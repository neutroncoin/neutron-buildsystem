#!/bin/bash
#
# Copyright (c) 2017-2018 The Swipp developers
# Copyright (c) 2019 The Neutron developers
#
# This file is part of The Neutron Build System.
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
# General build script for Neutron, supporting different platforms and
# flavors.

neutron_repo="https://github.com/neutroncoin/neutron.git"
osxcross_repo="https://github.com/tpoechtrager/osxcross.git"
osx_sdk="https://github.com/phracker/MacOSX-SDKs/releases/download/MacOSX10.11.sdk/MacOSX10.11.sdk.tar.xz"
hfsplus_repo="https://github.com/andreas56/libdmg-hfsplus.git"
mxe_repo="https://github.com/mxe/mxe.git"
return_code=0

pushd () {
	command pushd "$@" > /dev/null
}

popd () {
	command popd "$@" > /dev/null
}

cleanup() {
	kill $(jobs -p) &> /dev/null
	clear
}

choose_flavors() {
	current_distro=$(lsb_release -d | sed 's/Description:\s//g')

	dialog --stdout --checklist "Please choose which wallet flavor of Neutron you would like to build:" \
	       12 60 4 linux "Linux [$current_distro]" 0 \
	       osx   "MacOS X [10.11 (El Capitan)]" 0 \
	       win32 "Windows [32 bit]" 0 \
	       win64 "Windows [64 bit]" 0

	return $?
}

version="none"

choose_tags() {
	if [ $version != "none" ]; then
		return
	fi

	tags="$(git ls-remote --tags $neutron_repo | sed -n 's_^.*/\([^/}]*\)$_\1_p') master"

	for i in $tags; do
		if [ $i = "master" ]; then
			hash=$(git ls-remote $neutron_repo | grep master | cut -f1 | cut -b 1-7)
			tags_arguments=($hash "Master version ($hash)" off "${tags_arguments[@]}")
		else
			tags_arguments=($i "Tagged release $i" off "${tags_arguments[@]}")
		fi
	done

	tags_arguments[5]=on

	dialog --stdout --radiolist "Please choose which versions of Neutron you would like to build:" \
	       17 54 10 "${tags_arguments[@]}"

	return $?
}

checkout() {
	if [ $version == "none" ]; then
		version=master
	fi

	clear
	git checkout $version &> /dev/null

	if (($? != 0)); then
		dialog --msgbox "Failed to check out $version in repository $3" 7 70
		exit 1
	else
		git pull --force
	fi
}

#buildir_name, clone_dir, repo
clone() {
	if [ ! -d "build" ]; then
		mkdir build
	fi

	if [ ! -d "build/$1" ]; then
		mkdir build/$1-$version
	fi

	if [ ! -d "build/$1-$version/$2" ]; then
		clear
		git clone $3 build/$1-$version/$2

		if (($? != 0)); then
			dialog --msgbox "Failed to clone repository $3" 7 70
			exit 1
		fi
	fi
}

install_dependencies() {
	for i in $@; do
		dpkg -l $i &> /dev/null

		if [ $? -eq 1 ]; then
			missingdeps+=" $i"
		fi
	done

	missingdeps=${missingdeps:1}

	if [ -n "$missingdeps" ]; then
		dialog --msgbox "The dependencies '$missingdeps' are missing and need to be installed before running this script." 8 70
		exit 1
	fi
}

# percentage_span, logfile, errfile, logfile_max_len, jobs, pid
build_dialog() {
	range=($1)
	progress=$(eval "cat $2 | wc -l")
	span=$((${range[-1]}-${range[0]}))

	for i in $(eval echo {0..${#pjobs[@]}}); do
		if [ "${pjobs[$i]}" = "_" ]; then
			break
		fi
	done

	if [ $progress -eq 0 ]; then
		pjobs[$i]="3"
		dialog --title "$title" --mixedgauge " " 22 70 ${range[-1]} "${pjobs[@]}"
	fi

	while (( $progress < ${4} )); do
		percent=$(((100*$progress)/$4))
		percent=$(if (($percent > 100)); then echo 100; else echo $percent; fi) # clamp
		pjobs[$i]="-$percent"
		clear

		dialog --title "$title [$progress/${4}]" --mixedgauge " " 22 70 \
		       $((${range[0]}+($span*$percent)/100)) "${pjobs[@]}"

		if [ ! -d "/proc/$5" ]; then
			sleep 0.5
			return $return_code
		fi

		sleep 5

		if [ -f "$3" ] && [ -s "$3" ]; then
			if (( $(cat $3 | grep -E "error|ERROR" | wc -l) > 0 )); then
			    kill $6 &> /dev/null
				return 1
			fi
		fi

		progress=$(eval "cat $2 | wc -l")
	done

	wait $6
	return $return_code
}

# step, percentage_span, logfile, errfile
build_step() {
	pjobs[$1]="_"
	touch $3 $4

	if [ -n "${todo[0]}" ] && [ "${todo[0]}" -eq "${todo[0]}" ] 2> /dev/null; then
		todores="${todo[0]}"
	else
		todores=$(eval ${todo[0]} | wc -l)
	fi

	{
		eval ${todo[1]}
		return_code=$?
	} &

	build_dialog "$2" $3 $4 $todores $!
	pjobs[$1]=$(if (($? == 0)); then echo 3; else echo 1; fi)
}

pjobs_result() {
	failed="false"

	for i in "${pjobs[@]}"; do
		if [ "$i" -eq "$i" ] 2>/dev/null && [ "$i" -eq "1" ]; then
			failed="true"
		fi
	done

	if [ $failed == "false" ]; then
		touch $1
	fi
}

trap cleanup EXIT
dialog --textbox build-components/welcome.txt 22 70

choices=$(choose_flavors)
if [[ $choices == "" ]]; then
	exit 0
fi

version=$(choose_tags)
if [[ $version == "" ]]; then
	exit 0
fi

if [[ $choices =~ "linux" ]]; then
	title="Building Linux flavor"
	pjobs=("Creating build files from QMAKE file"   8 \
	       "Building native QT wallet"              8 \
	       "Building native console wallet"         8 \
	       "Generating cross-distro QT wallet"      8 \
	       "Generating cross-distro console wallet" 8)

	install_dependencies build-essential make g++ libboost-all-dev libssl1.0-dev libdb4.8++-dev \
	                     libminiupnpc-dev libz-dev libcurl4-openssl-dev qt5-default \
	                     qttools5-dev-tools

	clone linux neutron $neutron_repo
	pushd build
	pushd linux-$version
	pushd neutron
	checkout

	todo=(6 "qmake -Wnone neutron-qt.pro 2> ../qmake.error 1> ../qmake.log")
	build_step 1 "$(echo {0..5})" ../qmake.log ../qmake.error

	sh share/genbuild.sh build/build.h
	todo=("make -n 2> /dev/null" "make -j$(nproc) 2> ../make-qt.error 1> ../make-qt.log")
	build_step 3 "$(echo {5..60})" ../make-qt.log ../make-qt.error

	pushd src
	todo=("make -n -f makefile.unix 2> /dev/null | grep \"^\(cc\|g++\)\"" \
	      "make -j$(nproc) -f makefile.unix 2> ../../make-console.error 1> ../../make-console.log")
	build_step 5 "$(echo {60..80})" ../../make-console.log ../../make-console.error
	strip neutrond

	popd
	popd

	todo=(85 "../../build-components/neutron-linuxdeployqt.sh neutron Neutron-qt 2> linuxdeployqt-qt.log 1> /dev/null")
	build_step 7 "$(echo {80..90})" linuxdeployqt-qt.log linuxdeployqt-qt.error

	todo=(85 "../../build-components/neutron-linuxdeployqt.sh neutron/src neutrond 2> linuxdeployqt-console.log 1> /dev/null")
	build_step 9 "$(echo {90..100})" linuxdeployqt-console.log linuxdeployqt-console.error
	popd
	popd
fi

if [[ $choices =~ "win32" || $choices =~ "win64" ]]; then
	title="Preparing Windows dependencies"
	pjobs=("Building GCC and build environment" 8 \
	       "Building QT base dependencies"      8 \
	       "Building QT tools dependencies"     8 \
	       "Building CURL dependency"           8)

	clone win32 neutron $neutron_repo
	pushd build
	pushd win32-$version
	pushd neutron
	checkout
	popd
	clone win32 mxe $mxe_repo
	pushd mxe

	arg_mxe_path=.
	arg_target=i686-w64-mingw32.static
	targets="i686-w64-mingw32.static x86_64-w64-mingw32.static"
	source "../../../build-components/cross-compile-win.sh"

	todo=("make -n MXE_TARGETS=\"$targets\" cc | grep -o \"\[done\]\"" \
	      "make MXE_TARGETS=\"$targets\" -j$(nproc) cc 2> ../makedep-cc.error 1> ../makedep-cc.log")
	build_step 1 "$(echo {0..30})" ../makedep-cc.log ../makedep-cc.error

	todo=("make -n MXE_TARGETS=\"$targets\" qtbase | grep -o \"\[done\]\"" \
	      "make MXE_TARGETS=\"$targets\" -j$(nproc) qtbase 2> ../makedep-qtbase.error 1> ../makedep-qtbase.log")
	build_step 3 "$(echo {30..50})" ../makedep-qtbase.log ../makedep-qtbase.error

	todo=("make -n MXE_TARGETS=\"$targets\" qttools | grep -o \"\[done\]\"" \
	      "make MXE_TARGETS=\"$targets\" -j$(nproc) qttools 2> ../makedep-qttools.error 1> ../makedep-qttools.log")
	build_step 5 "$(echo {50..80})" ../makedep-qtbase.log ../makedep-qtbase.error

	todo=("make -n MXE_TARGETS=\"$targets\" curl | grep -o \"\[done\]\"" \
	      "make MXE_TARGETS=\"$targets\" -j$(nproc) curl 2> ../makedep-curl.error 1> ../makedep-curl.log")
	build_step 7 "$(echo {80..100})" ../makedep-curl.log ../makedep-curl.error

	popd
	popd
	popd
fi

if [[ $choices =~ "osx" ]]; then
	title="Preparing MacOS X dependencies"
	pjobs=("Building OSX cross toolchain" 8 \
	       "Installing OpenSSL"           8 \
	       "Installing BerkleyDB 4.8"     8 \
	       "Installing MiniUPNPC"         8 \
	       "Installing CURL"              8 \
	       "Installing QT5"               8 \
	       "Installing Boost"             8)

	clone osx neutron $neutron_repo
	clone osx osxcross $osxcross_repo
	clone osx libdmg-hfsplus $hfsplus_repo

	pushd build
	pushd osx-$version
	pushd neutron
	checkout
	popd
	pushd osxcross

	if [ ! -f ../.osx-prepared ]; then
		pushd tarballs
		wget --quiet -nc "$osx_sdk"
		popd
	fi

	if [ ! -f ../.osx-prepared ]; then
		# hard-coded 1000, no way to get the amount
		todo=(1000 "UNATTENDED=1 JOBS=$(nproc) ./build.sh 2> ../makedep-toolchain.error 1> ../makedep-toolchain.log")
		build_step 1 "$(echo {0..30})" ../makedep-toolchain.log ../makedep-toolchain.error
		PATH=$PATH:$(pwd)/target/bin

		# This configures the mirror
		UNATTENDED=1 MACOSX_DEPLOYMENT_TARGET=10.11 osxcross-macports search openssl &> /dev/null

		todo=(10 "UNATTENDED=1 MACOSX_DEPLOYMENT_TARGET=10.11 osxcross-macports install openssl 2> ../pkg-openssl.error 1> ../pkg-openssl.log")
		build_step 3 "$(echo {30..35})" ../pkg-openssl.log ../pkg-openssl.error

		todo=(5 "UNATTENDED=1 MACOSX_DEPLOYMENT_TARGET=10.11 osxcross-macports install db48 2> ../pkg-db48.error 1> ../pkg-db48.log")
		build_step 5 "$(echo {35..40})" ../pkg-db48.log ../pkg-db48.error

		todo=(5 "UNATTENDED=1 MACOSX_DEPLOYMENT_TARGET=10.11 osxcross-macports install miniupnpc 2> ../pkg-miniupnpc.error 1> ../pkg-miniupnpc.log")
		build_step 7 "$(echo {40..45})" ../pkg-miniupnpc.log ../pkg-miniupnpc.error

		todo=(63 "UNATTENDED=1 MACOSX_DEPLOYMENT_TARGET=10.11 osxcross-macports install curl 2> ../pkg-curl.error 1> ../pkg-curl.log")
		build_step 9 "$(echo {45..50})" ../pkg-curl.log ../pkg-curl.error

		todo=(319 "UNATTENDED=1 MACOSX_DEPLOYMENT_TARGET=10.11 osxcross-macports install qt57 2> ../pkg-qt57.error 1> ../pkg-qt57.log")
		build_step 11 "$(echo {50..90})" ../pkg-qt57.log ../pkg-qt57.error

		todo=(12 "UNATTENDED=1 MACOSX_DEPLOYMENT_TARGET=10.11 osxcross-macports install boost 2> ../pkg-boost.error 1> ../pkg-boost.log")
		build_step 13 "$(echo {90..100})" ../pkg-boost.log ../pkg-boost.error

		pjobs_result ../.osx-prepared
	fi

	popd
	pushd neutron

	title="Building MacOS X flavor"
	pjobs=("Creating build files from QMAKE file" 8 \
	       "Building native QT wallet"            8 \
	       "Preparing libdmg-hfsplus"             8 \
	       "Building libdmg-hfsplus"              8 \
	       "Preparing DMG archive"                8 \
	       "Generating DMG archive"               8)

	todo=(6 "unshare -r -m sh -c \"mount --bind $(pwd)/../../../build-components/qmake.conf /usr/lib/x86_64-linux-gnu/qt5/mkspecs/macx-clang/qmake.conf; CUSTOM_SDK_PATH=$(pwd)/../osxcross/target/SDK/MacOSX10.11.sdk CUSTOM_MIN_DEPLOYMENT_TARGET=10.11 qmake -spec macx-clang QMAKE_DEFAULT_INCDIRS=\"\" QMAKE_CC=$(pwd)/../osxcross/target/bin/x86_64-apple-darwin15-clang QMAKE_CXX=$(pwd)/../osxcross/target/bin/x86_64-apple-darwin15-clang++-libc++ QMAKE_LINK=$(pwd)/../osxcross/target/bin/x86_64-apple-darwin15-clang++-libc++ BOOST_INCLUDE_PATH=$(pwd)/../osxcross/target/macports/pkgs/opt/local/include/ BOOST_LIB_PATH=$(pwd)/../osxcross/target/macports/pkgs/opt/local/lib/ BOOST_LIB_SUFFIX=-mt BDB_INCLUDE_PATH=$(pwd)/../osxcross/target/macports/pkgs/opt/local/include/db48/ BDB_LIB_PATH=$(pwd)/../osxcross/target/macports/pkgs/opt/local/lib/db48/ BDB_LIB_SUFFIX=-4.8 neutron-qt.pro 2> ../qmake.error 1> ../qmake.log\"")
	build_step 1 "$(echo {0..5})" ../qmake.log ../qmake.error

	sed -i 's/\/usr\/include\/x86_64-linux-gnu\/qt5/..\/osxcross\/target\/macports\/pkgs\/opt\/local\/libexec\/qt5\/include/g' Makefile
	sed -i 's/-o build\/moc_bitcoingui.cpp/-DQ_OS_MAC -o build\/moc_bitcoingui.cpp/g' Makefile
	sed -i 's/ -L\/usr\/lib\/x86_64-linux-gnu//g' Makefile
	sed -i 's/ -lQt5PrintSupport//g' Makefile
	sed -i 's/ -lQt5Widgets//g' Makefile
	sed -i 's/ -lQt5Gui//g' Makefile
	sed -i 's/ -lQt5Network//g' Makefile
	sed -i 's/ -lQt5Core//g' Makefile
	ln -s /usr/include/c++/v1 $(pwd)/../osxcross/target/SDK/MacOSX10.11.sdk/usr/include/c++/v1 &> /dev/null

	sh share/genbuild.sh build/build.h
	todo=("TARGET_OS=Darwin make -n 2> /dev/null" "TARGET_OS=Darwin make -j$(nproc) 2> ../make-qt.error 1> ../make-qt.log")
	build_step 3 "$(echo {5..75})" ../make-qt.log ../make-qt.error

	popd
	pushd libdmg-hfsplus

	todo=(22 "cmake . 2> ../cmake-libdmg-hfsplus.error 1> ../cmake-libdmg-hfsplus.log")
	build_step 5 "$(echo {75..80})" ../cmake-libdmg-hfsplus.log ../cmake-libdmg-hfsplus.error

	todo=(37 "make -j$(nproc) 2> ../make-libdmg-hfsplus.error 1> ../make-libdmg-hfsplus.log")
	build_step 7 "$(echo {80..85})" ../make-libdmg-hfsplus.log ../make-libdmg-hfsplus.error

	popd

	#todo(99 "unshare -r -m sh -c \"mount --bind osxcross/target/macports/pkgs/opt /opt; INSTALLNAMETOOL=osxcross/target/bin/x86_64-apple-darwin15-install_name_tool OTOOL=osxcross/target/bin/x86_64-apple-darwin15-otool STRIP=osxcross/target/bin/x86_64-apple-darwin15-strip ../../build-components/macdeployqtplus -verbose 2 neutron/Neutron-Qt.app -add-resources neutron/src/qt/locale\"")
	#build_step 9 "$(echo {85..90})" macdeployqtplus.log macdeployqtplus.error

	#todo(1385 "PATH=$PATH:$(pwd)/libdmg-hfsplus/dmg:$(pwd)/libdmg-hfsplus/hfs ../../build-components/create-dmg.sh dist/Neutron-Qt.app neutron-master")
	build_step 11 "$(echo {90..100})" create-dmg.log create-dmg.error

	popd
	popd
fi

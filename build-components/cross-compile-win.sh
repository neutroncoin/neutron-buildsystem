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
# Cross compilation script for Neutron using MXE (M cross environment)
# To run this script, you need to have a complete MXE distribution
# installed with the following dependencies compiled:
#
# make MXE_TARGETS="i686-w64-mingw32.static" boost
# make MXE_TARGETS="i686-w64-mingw32.static" qtbase
# make MXE_TARGETS="i686-w64-mingw32.static" qttools
# make MXE_TARGETS="i686-w64-mingw32.static" curl
#
# $1: Location of MXE
# $2: Target (should be either i686-w64-mingw32.static, x86_64-w64-mingw32.static or x86_64-w64-minigw32.static.posix)
# --compile: Compile main executable
# --compile-dependencies: Compile dependencies

if [ "$0" = "$BASH_SOURCE" ]; then
	if [ ! -d "$1" ]; then
		echo ERROR: The directory $1 does not exist
		exit 1
	fi

	if [ -z "$2" ]; then
		echo ERROR: No MXE target specified
		exit 1
	fi

	arg_mxe_path=$1
	arg_target=$2
fi

PATH=$arg_mxe_path/usr/$arg_target/bin:$PATH
MXE_INCLUDE_PATH=$arg_mxe_path/usr/$arg_target/include
MXE_LIB_PATH=$arg_mxe_path/usr/$arg_target/lib

win_qmake() {
	$2-qt5 \
		BOOST_LIB_SUFFIX=-mt \
		BOOST_THREAD_LIB_SUFFIX=_win32-mt \
		BOOST_INCLUDE_PATH=$MXE_INCLUDE_PATH/boost \
		BOOST_LIB_PATH=$MXE_LIB_PATH \
		OPENSSL_INCLUDE_PATH=$MXE_INCLUDE_PATH/openssl \
		OPENSSL_LIB_PATH=$MXE_LIB_PATH \
		BDB_INCLUDE_PATH=$MXE_INCLUDE_PATH \
		BDB_LIB_PATH=$MXE_LIB_PATH \
		MINIUPNPC_INCLUDE_PATH=$MXE_INCLUDE_PATH \
		MINIUPNPC_LIB_PATH=$MXE_LIB_PATH \
		CURL_LIB_PATH=$MXE_LIB_PATH \
		QMAKE_LRELEASE=$1/usr/$2/qt5/bin/lrelease \
		MXE=1 USE_QRCODE=1 USE_UPNP=1 RELEASE=1 USE_BUILD_INFOP=1 \
		neutron-qt.pro
}

win_leveldb() {
	pushd src/leveldb
	TARGET_OS=NATIVE_WINDOWS make -j$(($(nproc)/2)) out-static/libleveldb.a out-static/libmemenv.a \
		CC=$1/usr/bin/$2-gcc \
		CXX=$1/usr/bin/$2-g++
	popd
}

win_sec256k1() {
	pushd ../secp256k1
	./autogen.sh
	./configure --host=$1
	make -j$(($(nproc)/2))
	popd
}

win_main() {
	make -j$(($(nproc)/2)) -f Makefile.Release
}

if [[ "$@" == "--compile-dependencies" ]]; then
	make MXE_TARGETS="$arg_target" boost
	make MXE_TARGETS="$arg_target" qtbase
	make MXE_TARGETS="$arg_target" qttools
	make MXE_TARGETS="$arg_target" curl
fi

if [[ "$@" == "--compile" ]]; then
	win_qmake $arg_mxe_path $arg_target
	win_leveldb $arg_mxe_path $arg_target
	win_sec256k1 $arg_target
	win_main
fi

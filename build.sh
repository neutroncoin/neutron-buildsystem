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
dist=$(lsb_release -i | cut -f2 -d$'\t')
dist_version=$(lsb_release -c | cut -f2 -d$'\t')
return_code=0

pushd () {
	command pushd "$@" > /dev/null
}

popd () {
	command popd "$@" > /dev/null
}

cleanup() {
	kill $(jobs -p) &> /dev/null
	echo
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

	tags="$(git ls-remote --tags $neutron_repo | sed -n 's_^.*/\([^/}]*\)$_\1_p' | sort -V) master"

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
		git pull --force &> /dev/null
	fi
}

#buildir_name, clone_dir, repo
clone() {
	if [ ! -d "build" ]; then
		mkdir build
	fi

	if [ ! -d "build/$1-$version" ]; then
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

#clone_dir, repo
clone_toolchain() {
	if [ ! -d "build" ]; then
		mkdir build
	fi

        if [ ! -d "build/$1" ]; then
                clear
                git clone $2 build/$1

                if (($? != 0)); then
                        dialog --msgbox "Failed to clone repository $2" 7 70
                        exit 1
                fi
        fi
}

collect_dependencies() {
	for i in $@; do
		dpkg -s $i &> /dev/null

		if [ $? -eq 1 ]; then
			missingdeps+=" $i"
		fi
	done
}

install_dependencies() {
	missingdeps=${missingdeps:1}
	authenticated="false"

	if [ -n "$missingdeps" ]; then
		if [[ $1 == "text" ]]; then
			echo -n "The dependencies '$missingdeps' are needed to run this script. Would you like to install them? (y/n) "
			read -n1 -r reply
			echo ""
		else
			dialog --yesno "The dependencies '$missingdeps' are missing and need to be installed. Would you like to install them?" 8 70
		fi

		if [[ ( $? -eq 0 && $1 != "text" )  || $reply =~ ^[Yy]$ ]]; then
			apt_command=""

			if [ ! -f /etc/apt/sources.list.d/mxe.list ] && [[ $choices =~ "win32" || $choices =~ "win64" ]]; then
				apt_command+="echo \"deb file://$(pwd)/build-components/mxe-repo $dist_version main\" > /etc/apt/sources.list.d/mxe.list && "
				apt_command+="apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 86B72ED9 && "
			fi

			tmp_dist_version=$dist_version

			# Special side-case to support Debian
			if [[ $dist == "Debian" ]]; then
				tmp_dist_version="bionic"
			fi

			if [ ! -f /etc/apt/sources.list.d/bitcoin.list ] && [[ $missingdeps =~ "libdb4.8++-dev" ]] && [[ $choices =~ "linux" ]]; then
				apt_command+="echo \"deb http://ppa.launchpad.net/bitcoin/bitcoin/ubuntu $tmp_dist_version main\" > /etc/apt/sources.list.d/bitcoin.list && "
				apt_command+="apt-key adv --keyserver keyserver.ubuntu.com --recv-keys C70EF1F0305A1ADB9986DBD8D46F45428842CE5E && "
			fi

			apt_command+="apt-get -qy update && apt-get -qy --no-install-recommends install $missingdeps"

			# Strip the main function from libminiupnpc

			if [[ $missingdeps =~ "mxe-i686-w64-mingw32.static-miniupnpc" ]]; then
				apt_command+="&& /usr/lib/mxe/usr/bin/i686-w64-mingw32.static-ar dv /usr/lib/mxe/usr/i686-w64-mingw32.static/lib/libminiupnpc.a upnpc.c.obj &> /dev/null"
			fi

			if [[ $missingdeps =~ "mxe-x86-64-w64-mingw32.static-miniupnpc" ]]; then
				apt_command+="&& /usr/lib/mxe/usr/bin/x86_64-w64-mingw32.static-ar dv /usr/lib/mxe/usr/x86_64-w64-mingw32.static/lib/libminiupnpc.a upnpc.c.obj &> /dev/null"
			fi

			if [[ $USER == "root" ]]; then
				authenticated="true"
				su -c "$apt_command"
			elif [[ $dist == "Debian" ]]; then
				clear
				echo Please provide root password to install dependencies

				if [ $? -eq 0 ]; then
					authenticated="true"
					su -c "$apt_command"
				fi
			else
				groups | grep "sudo"

				# If we are in the sudo group we assume we have root privileges
				if [ $? -eq 0 ]; then
					echo Please provide your password to install dependencies as administrator

					if [ $? -eq 0 ]; then
						authenticated="true"
						sudo $apt_command
					fi
				else
					notsudo="You are not in the sudo group and can therefore not install any dependencies. Please install the required dependencies as super user before executing this script."
					if [[ $1 == "text" ]]; then
						echo $notsudo
					else
						dialog --msgbox "$notsudo" 8 70
					fi
				fi

				if [[ $authenticated == "false" ]]; then
					exit 1
				fi
			fi
		else
			exit 1
		fi

		if [ $? -eq 1 ]; then
			echo "Failed to install required  dependencies... Exiting build environment."
			exit 1
		fi
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

#version
gather_releases() {
	if [ ! -d "releases" ]; then
		mkdir releases
	fi

	if [[ $choices =~ "linux" ]]; then
		if [[ -f build/linux-$version/neutrond-x86_64.AppImage ]]; then
			cp build/linux-$version/neutrond-x86_64.AppImage releases/neutrond-$version-linux-x86_64.AppImage &> /dev/null
		fi

		if [[ -f build/linux-$version/Neutron-qt-x86_64.AppImage ]]; then
			cp build/linux-$version/Neutron-qt-x86_64.AppImage releases/Neutron-qt-$version-linux-x86_64.AppImage &> /dev/null
		fi
	fi

	if [[ $choices =~ "osx" ]]; then
		if [[ -f build/osx-$version/Neutron-qt-$version.dmg ]]; then
			cp build/osx-$version/Neutron-qt-$version.dmg releases/Neutron-qt-$version-osx.dmg &> /dev/null
		fi
	fi

	if [[ $choices =~ "win32" ]]; then
		if [[ -f build/win32-$version/neutron/release/Neutron-qt.exe ]]; then
			clear
			7z a -t7z -mx9 -y releases/Neutron-qt-$version-win32.7z ./build/win32-$version/neutron/release/Neutron-qt.exe
			clear
		fi
	fi

	if [[ $choices =~ "win64" ]]; then
		if [[ -f build/win64-$version/neutron/release/Neutron-qt.exe ]]; then
			clear
			7z a -t7z -mx9 -y releases/Neutron-qt-$version-win64.7z ./build/win64-$version/neutron/release/Neutron-qt.exe
			clear
		fi
	fi
}

check_compatibility() {
	supported="Debian Stretch, Ubuntu Bionic, Ubuntu Trusty, Ubuntu Xenial"

	if [[ ! ${supported,,} =~ "${dist,,} ${dist_version,,}" ]]; then
		cwarning="WARNING: Unsupported distribution"
		ctext="The build system has detected the following host distribution:\n\Zb$dist $dist_version\Zn\n\nPlease note that this distribution is unsupported by the build system and may cause the build environment to fail during the compilation of Neutron. At the moment, the build system supports the following distributions and versions: \Zb$supported\Zn\n\nContinuing from this point may or may not work depending on the compatibility of the host distribution."
		if hash dialog &> /dev/null; then
			dialog --colors --title "$cwarning" --msgbox "$ctext" 16 70
		else
			echo -e "$cwarning\n"
			ctext=${ctext//\\Zb/}
			echo -e "${ctext//\\Zn/}"
			echo -n "Please press any key to continue... "
			read -n1
		fi
	fi
}

#Can this version and distro of Linux run this build system?
check_compatibility

# Check for "dialog" before we try to use it
collect_dependencies dialog
install_dependencies text
missing_deps=""

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

# First we collect all general dependencies....
collect_dependencies wget git autoconf automake make pkg-config cmake g++ p7zip-full

# Next collect the dependencies for the active choices
if [[ $choices =~ "linux" ]]; then
	collect_dependencies build-essential libboost-all-dev libssl1.0-dev libdb4.8++-dev \
	                     libdb4.8-dev libminiupnpc-dev zlib1g-dev qt5-default \
	                     qttools5-dev-tools qt5-qmake
fi

if [[ $choices =~ "win32" || $choices =~ "win64" ]]; then
	collect_dependencies autopoint bison bzip2 flex gettext gperf intltool libffi-dev libtool \
                             libltdl-dev libxml-parser-perl patch perl p7zip-full python ruby sed unzip \
                             xz-utils g++-multilib libc6-dev-i386 libtool-bin \
	                     mxe-source
fi

if [[ $choices =~ "win32" ]]; then
	collect_dependencies mxe-i686-w64-mingw32.static-qtbase mxe-i686-w64-mingw32.static-qttools mxe-i686-w64-mingw32.static-boost \
	                     mxe-i686-w64-mingw32.static-miniupnpc mxe-i686-w64-mingw32.static-libqrencode
fi

if [[ $choices =~ "win64" ]]; then
	collect_dependencies mxe-x86-64-w64-mingw32.static-qtbase mxe-x86-64-w64-mingw32.static-qttools mxe-x86-64-w64-mingw32.static-boost \
	                     mxe-x86-64-w64-mingw32.static-miniupnpc mxe-x86-64-w64-mingw32.static-libqrencode
fi

if [[ $choices =~ "osx" ]]; then
	collect_dependencies clang libxml2-dev libc++-dev libbz2-dev hfsprogs
fi

install_dependencies

if [[ $choices =~ "linux" ]]; then
	title="Building Linux flavor"
	pjobs=("Creating build files from QMAKE file"   8 \
	       "Building native QT wallet"              8 \
	       "Building native console wallet"         8 \
	       "Generating cross-distro QT wallet"      8 \
	       "Generating cross-distro console wallet" 8)

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

#target, flavor_version
build_windows() {
	target="$1"
	title="Preparing Windows $2 flavor"

	clone win$2 neutron $neutron_repo
	pushd build
	pushd win$2-$version
	pushd neutron
	checkout
	popd
	popd

	if [ ! -f win$2-db-4.8.30 ]; then
		tar xvfz ../build-components/dependencies/db-4.8.30.tar.gz &> /dev/null
		mv db-4.8.30 win$2-db-4.8.30 &> /dev/null
		mkdir win$2-db-4.8.30/build_mxe &> /dev/null
	fi

	if [ ! -f .win$2-prepared ]; then
		pjobs=("Buidling BerkleyDB 4.8" 8)
		pushd win$2-db-4.8.30
		pushd build_mxe
		todo=(854 "../../../build-components/cross-compile-win.sh /usr/lib/mxe $target --berkleydb 2> ../../win$2-db.error 1> ../../win$2-db.log")
		build_step 1 "$(echo {0..100})" ../../win$2-db.log ../../win$2-db.error
		popd
		popd
	fi

	title="Building Windows $2 flavor"
	pjobs=("Creating build files from QMAKE file" 8 \
	       "Building native QT wallet"            8)

	pushd win$2-$version
	pushd neutron

	cp ../../../build-components/opensslcompat.c ../../../build-components/opensslcompat.h src/ &> /dev/null
	git apply ../../../build-components/opensslcompat.patch &> /dev/null

	sed -i 's/i686-w64-mingw32.static/$$HOST/g' neutron-qt.pro

	todo=(18 "BDB_INCLUDE_PATH=$(pwd)/../../win$2-db-4.8.30/build_mxe BDB_LIB_PATH=$(pwd)/../../win$2-db-4.8.30/build_mxe ../../../build-components/cross-compile-win.sh /usr/lib/mxe $target --qmake 2> ../qmake.error 1> ../qmake.log")
	build_step 1 "$(echo {0..10})" ../qmake.log ../qmake.error

	todo=(400 "../../../build-components/cross-compile-win.sh /usr/lib/mxe $target --compile-main 2> ../make-qt.error 1> ../make-qt.log")
	build_step 3 "$(echo {10..100})" ../make-qt.log ../make-qt.error

	popd
	popd
	popd
}

if [[ $choices =~ "win32" ]]; then
	build_windows i686-w64-mingw32.static 32
fi

if [[ $choices =~ "win64" ]]; then
	build_windows x86_64-w64-mingw32.static 64
fi

if [[ $choices =~ "osx" ]]; then
	title="Preparing MacOS X dependencies"
	pjobs=("Building OSX cross toolchain" 8 \
	       "Installing OpenSSL"           8 \
	       "Installing BerkleyDB 4.8"     8 \
	       "Installing MiniUPNPC"         8 \
	       "Installing CURL"              8 \
	       "Installing QT5"               8 \
	       "Installing Boost"             8 \
	       "Installing ICU"               8 \
	       "Preparing libdmg-hfsplus"     8 \
	       "Building libdmg-hfsplus"      8)

	clone osx neutron $neutron_repo
	clone_toolchain osx-osxcross $osxcross_repo
	clone_toolchain osx-libdmg-hfsplus $hfsplus_repo

	pushd build
	pushd osx-$version
	pushd neutron
	checkout
	popd
	popd
	pushd osx-osxcross

	if [ ! -f ../.osx-prepared ]; then
		pushd tarballs
		wget --quiet -nc "$osx_sdk"
		popd
	fi

	PATH=$PATH:$(pwd)/target/bin

	if [ ! -f ../.osx-prepared ]; then
		# hard-coded 2300, no way to get the amount
		todo=(2300 "UNATTENDED=1 JOBS=$(nproc) ./build.sh 2> ../osx-makedep-toolchain.error 1> ../osx-makedep-toolchain.log")
		build_step 1 "$(echo {0..30})" ../osx-makedep-toolchain.log ../osx-makedep-toolchain.error

		# This configures the mirror
		UNATTENDED=1 MACOSX_DEPLOYMENT_TARGET=10.11 osxcross-macports search openssl10 &> /dev/null

		todo=(10 "UNATTENDED=1 MACOSX_DEPLOYMENT_TARGET=10.11 osxcross-macports install openssl10 2> ../osx-pkg-openssl.error 1> ../osx-pkg-openssl.log")
		build_step 3 "$(echo {30..35})" ../osx-pkg-openssl.log ../osx-pkg-openssl.error

		todo=(5 "UNATTENDED=1 MACOSX_DEPLOYMENT_TARGET=10.11 osxcross-macports install db48 2> ../osx-pkg-db48.error 1> ../osx-pkg-db48.log")
		build_step 5 "$(echo {35..40})" ../osx-pkg-db48.log ../osx-pkg-db48.error

		todo=(5 "UNATTENDED=1 MACOSX_DEPLOYMENT_TARGET=10.11 osxcross-macports install miniupnpc 2> ../osx-pkg-miniupnpc.error 1> ../osx-pkg-miniupnpc.log")
		build_step 7 "$(echo {40..45})" ../osx-pkg-miniupnpc.log ../osx-pkg-miniupnpc.error

		todo=(63 "UNATTENDED=1 MACOSX_DEPLOYMENT_TARGET=10.11 osxcross-macports install curl 2> ../osx-pkg-curl.error 1> ../osx-pkg-curl.log")
		build_step 9 "$(echo {45..50})" ../osx-pkg-curl.log ../osx-pkg-curl.error

		todo=(319 "UNATTENDED=1 MACOSX_DEPLOYMENT_TARGET=10.11 osxcross-macports install qt57 2> ../osx-pkg-qt57.error 1> ../osx-pkg-qt57.log")
		build_step 11 "$(echo {50..80})" ../osx-pkg-qt57.log ../osx-pkg-qt57.error

		todo=(12 "UNATTENDED=1 MACOSX_DEPLOYMENT_TARGET=10.11 osxcross-macports install boost169 2> ../osx-pkg-boost.error 1> ../osx-pkg-boost.log")
		build_step 13 "$(echo {80..85})" ../osx-pkg-boost.log ../osx-pkg-boost.error

		todo=(12 "UNATTENDED=1 MACOSX_DEPLOYMENT_TARGET=10.11 osxcross-macports install icu58 2> ../osx-pkg-icu.error 1> ../osx-pkg-icu.log")
		build_step 15 "$(echo {85..90})" ../osx-pkg-icu.log ../osx-pkg-icu.error

		popd
		cp osx-osxcross/target/macports/pkgs/opt/local/libexec/icu58/lib/libic*.58.dylib osx-osxcross/target/macports/pkgs/opt/local/lib/
		pushd osx-libdmg-hfsplus

		todo=(22 "cmake . 2> ../osx-cmake-libdmg-hfsplus.error 1> ../osx-cmake-libdmg-hfsplus.log")
		build_step 17 "$(echo {90..95})" ../osx-cmake-libdmg-hfsplus.log ../osx-cmake-libdmg-hfsplus.error

		todo=(37 "make -j$(nproc) 2> ../osx-make-libdmg-hfsplus.error 1> ../osx-make-libdmg-hfsplus.log")
		build_step 19 "$(echo {95..100})" ../osx-make-libdmg-hfsplus.log ../osx-make-libdmg-hfsplus.error

		popd
		pjobs_result .osx-prepared
		pushd osx-osxcross
	fi

	popd
	pushd osx-$version
	pushd neutron

	title="Building MacOS X flavor"
	pjobs=("Creating build files from QMAKE file" 8 \
	       "Building native QT wallet"            8 \
	       "Preparing DMG archive"                8 \
	       "Generating DMG archive"               8)

	sed -i 's/CC=$$QMAKE_CC CXX=$$QMAKE_CXX/CC=$$QMAKE_CC AR=$$first(QMAKE_AR) CXX=$$QMAKE_CXX/g' neutron-qt.pro

	todo=(6 "unshare -r -m sh -c \"mount --bind $(pwd)/../../../build-components/qmake.conf /usr/lib/x86_64-linux-gnu/qt5/mkspecs/macx-clang/qmake.conf; CUSTOM_SDK_PATH=$(pwd)/../../osx-osxcross/target/SDK/MacOSX10.11.sdk CUSTOM_MIN_DEPLOYMENT_TARGET=10.11 qmake -spec macx-clang QMAKE_DEFAULT_INCDIRS=\"\" QMAKE_CC=$(pwd)/../../osx-osxcross/target/bin/x86_64-apple-darwin15-clang QMAKE_CXX=$(pwd)/../../osx-osxcross/target/bin/x86_64-apple-darwin15-clang++-libc++ QMAKE_LINK=$(pwd)/../../osx-osxcross/target/bin/x86_64-apple-darwin15-clang++-libc++ BOOST_INCLUDE_PATH=$(pwd)/../../osx-osxcross/target/macports/pkgs/opt/local/libexec/boost169/include/ BOOST_LIB_PATH=$(pwd)/../../osx-osxcross/target/macports/pkgs/opt/local/libexec/boost169/lib/ BOOST_LIB_SUFFIX=-mt BDB_INCLUDE_PATH=$(pwd)/../../osx-osxcross/target/macports/pkgs/opt/local/include/db48/ BDB_LIB_PATH=$(pwd)/../../osx-osxcross/target/macports/pkgs/opt/local/lib/db48/ BDB_LIB_SUFFIX=-4.8 OPENSSL_INCLUDE_PATH=$(pwd)/../../osx-osxcross/target/macports/pkgs/opt/local/include/openssl-1.0 OPENSSL_LIB_PATH=$(pwd)/../../osx-osxcross/target/macports/pkgs/opt/local/lib/openssl-1.0/ MINIUPNPC_INCLUDE_PATH=$(pwd)/../../osx-osxcross/target/macports/pkgs/opt/local/include/ MINIUPNPC_LIB_PATH=$(pwd)/../../osx-osxcross/target/macports/pkgs/opt/local/lib/ neutron-qt.pro 2> ../qmake.error 1> ../qmake.log\"")
	build_step 1 "$(echo {0..5})" ../qmake.log ../qmake.error

	sed -i 's/\/usr\/include\/x86_64-linux-gnu\/qt5/..\/..\/osx-osxcross\/target\/macports\/pkgs\/opt\/local\/libexec\/qt5\/include/g' Makefile
	sed -i 's/-o build\/moc_bitcoingui.cpp/-DQ_OS_MAC -o build\/moc_bitcoingui.cpp/g' Makefile
	sed -i 's/ -L\/usr\/lib\/x86_64-linux-gnu//g' Makefile
	sed -i 's/ -lQt5PrintSupport//g' Makefile
	sed -i 's/ -lQt5Widgets//g' Makefile
	sed -i 's/ -lQt5Gui//g' Makefile
	sed -i 's/ -lQt5Network//g' Makefile
	sed -i 's/ -lQt5Core//g' Makefile
	ln -s /usr/include/c++/v1 $(pwd)/../../osx-osxcross/target/SDK/MacOSX10.11.sdk/usr/include/c++/v1 &> /dev/null

	# Make sure libssl1.0 lib directory is first, otherwise it will link with a newer version of OpenSSL
	pwdsed=$(echo $(pwd) | sed 's_/_\\/_g')
	sed -i 's/ -I..\/..\/osx-osxcross\/target\/macports\/pkgs\/opt\/local\/include / -I..\/..\/osx-osxcross\/target\/macports\/pkgs\/opt\/local\/include\/openssl-1.0 -I..\/..\/osx-osxcross\/target\/macports\/pkgs\/opt\/local\/include /g' Makefile
	sed -i "s/univalue -L$pwdsed\/..\/..\/osx-osxcross\/target\/macports\/pkgs\/opt\/local\/lib\//univalue -L$pwdsed\/..\/..\/osx-osxcross\/target\/macports\/pkgs\/opt\/local\/lib\/openssl-1.0\/ -L$pwdsed\/..\/..\/osx-osxcross\/target\/macports\/pkgs\/opt\/local\/lib\//g" Makefile

	# Code fixes for clang and OSX
	sed -i 's/clock_gettime( CLOCK_REALTIME,&tsp);/clock_serv_t cclock; mach_timespec_t mts; host_get_clock_service(mach_host_self(), CALENDAR_CLOCK, \&cclock); clock_get_time(cclock, \&mts); mach_port_deallocate(mach_task_self(), cclock); tsp.tv_sec = mts.tv_sec; tsp.tv_nsec = mts.tv_nsec;/g' src/util.cpp
	sed -i ':a;N;$!ba;s/#include "ui_interface.h"\n#include <boost\/algorithm\/string\/join.hpp>/#include "ui_interface.h"\n#include <mach\/clock.h>\n#include <mach\/mach.h>\n#include <boost\/algorithm\/string\/join.hpp>/g' src/util.cpp

	sh share/genbuild.sh build/build.h
	todo=("TARGET_OS=Darwin make -n 2> /dev/null" "TARGET_OS=Darwin make -j$(nproc) 2> ../make-qt.error 1> ../make-qt.log")
	build_step 3 "$(echo {5..75})" ../make-qt.log ../make-qt.error

	popd

	todo=(99 "unshare -r -m sh -c \"mount --bind ../osx-osxcross/target/macports/pkgs/opt /opt; INSTALLNAMETOOL=../osx-osxcross/target/bin/x86_64-apple-darwin15-install_name_tool OTOOL=../osx-osxcross/target/bin/x86_64-apple-darwin15-otool STRIP=../osx-osxcross/target/bin/x86_64-apple-darwin15-strip ../../build-components/macdeployqtplus -verbose 2 neutron/Neutron-qt.app -add-resources neutron/src/qt/locale 2> macdeployqtplus.error 1> macdeployqtplus.log\"")
	build_step 5 "$(echo {85..90})" macdeployqtplus.log macdeployqtplus.error

	todo=(406 "PATH=$PATH:$(pwd)/../osx-libdmg-hfsplus/dmg:$(pwd)/../osx-libdmg-hfsplus/hfs ../../build-components/create-dmg.sh dist Neutron-qt-$version 2> create-dmg.error 1> create-dmg.log")
	build_step 7 "$(echo {90..100})" create-dmg.log create-dmg.error

	popd
	popd
fi

gather_releases

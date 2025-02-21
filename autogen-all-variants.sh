#!/usr/bin/env bash
#
# Project    : ipv6calc
# File       : autogen-all-variants.sh
# Copyright  : 2011-2023 by Peter Bieringer <pb (at) bieringer.de>
#
# Information: run autogen.sh with all supported variants
#
# history: can run also through various version of GeoIP (-g) and IP2Location (-i) libraries
#  see autogen-support.sh for details

status_file="autogen-all-variants.status"

## Generate configure variants
autogen_variants() {
	autogen_variants_list

	autogen_variants_list | while IFS="#" read token options; do
		options_extra=""
		if [[ $token =~ APACHE ]]; then
			# https://github.com/pbiering/ipv6calc/issues/45
			options_extra=" --disable-mod_ipv6calc"
		fi
		echo "$token#${options:+$options } --clang$options_extra"
	done

	case "$OSTYPE" in
	    freebsd*)
		# skip 32-bit builds on FreeBSD
		return
		;;
	esac

	# 32-bit builds
	autogen_variants_list  | while IFS="#" read token options; do
		if [ -e /etc/redhat-release ]; then
			if grep -E -q "(CentOS|Red Hat|Alma|Rocky)" /etc/redhat-release; then
				if [[ $token =~ IP2LOCATION ]]; then
					# skip 32-bit builds on Enterprise Linux as IP2Location devel is not built for i686 on EPEL
					continue
				fi
			fi
		fi

		echo "$token#${options:+$options } --m32"
	done

	# 32-bit builds with clang
	autogen_variants_list  | while IFS="#" read token options; do
		if [[ $token =~ APACHE ]]; then
			# https://github.com/pbiering/ipv6calc/issues/45
			options_extra=" --disable-mod_ipv6calc"
		fi

		if [ -e /etc/redhat-release ]; then
			if grep -E -q "(CentOS|Red Hat|Alma|Rocky)" /etc/redhat-release; then
				if [[ $token =~ IP2LOCATION ]]; then
					# skip 32-bit builds on Enterprise Linux as IP2Location devel is not built for i686 on EPEL
					continue
				fi
			fi
		fi

		echo "$token#${options:+$options } --clang --m32$options_extra"
	done
}

autogen_variants_list() {
	if ! $skip_main_test; then
		cat <<END | grep -v ^#
NONE#
NONE#--external
BUNDLED#--enable-bundled-md5 --enable-bundled-getopt
OPENSSL#--enable-openssl-md5 --no-static-build
OPENSSL#--enable-openssl-evp-md5
LIBMD#--enable-libmd-md5 --no-static-build
IP2LOCATION#-i
IP2LOCATION#-I
GEOIP2 DBIP2#-m
GEOIP2 DBIP2#-M
GEOIP2#-m --disable-dbip2
GEOIP2#-M --disable-dbip2
DBIP2#-m --disable-geoip2
DBIP2#-M --disable-geoip2
APACHE IP2LOCATION GEOIP2 DBIP2#-a
APACHE IP2LOCATION GEOIP2 DBIP2#-A
NONE#--disable-db-ieee
NONE#--disable-db-ipv4
NONE#--disable-db-ipv6
NONE#--disable-db-ipv6 --disable-db-ipv4
NONE#--disable-db-ipv6 --disable-db-ipv4 --disable-db-ieee
NONE#--disable-db-ipv6 --disable-db-ipv4 --disable-db-ieee --disable-as-registry
NONE#--disable-db-ipv6 --disable-db-ipv4 --disable-db-ieee --disable-cc-registry
NONE#--disable-db-ipv6 --disable-db-ipv4 --disable-db-ieee --disable-as-registry --disable-cc-registry
NONE#--disable-db-ipv6 --disable-db-ieee
NONE#--disable-db-ipv4 --disable-db-ieee
NONE#--disable-db-builtin
END
	fi

	if $ip2location_versions_test; then
		for version in $ip2location_versions; do
			[ ${version:0:1} = "!" ] && continue
			local testlist=""
			local option=""
			for version_test in $ip2location_versions; do
				if [ "$dynamic_load" = "1" ]; then
					option="--ip2location-dyn"
					# unconditionally test all versions
					testlist="$testlist I:$version_test"
				else
					[ ${version_test:0:1} = "!" ] && continue
					if ip2location_cross_version_test_blacklist $version $version_test; then
						testlist="$testlist I:$version_test"
					fi
				fi
			done
			echo "IP2LOCATION#--enable-ip2location $option $(options_from_name_version IP2Location $version)#$testlist"
		done
	fi
}

help() {
	cat <<END
$0
	-h|-?	this online help
	-f	force new run, remove status file unconditionally
	-r	force re-run, after finished one, remove status file
	-N	add --no-static-build to autogen.sh
	-I	skip IP2Location builds using system wide available library
	-i	run through internal defined IP2Location versions
	-D	enable dynamic library loading in run through versions	
	-M	skip main tests
	-n	dry-run, show only what would be build
	-c	cross version test
	-b	batch test (do not stop on error)
END
}


batch=false
cross_versions_test=false
dry_run=false
dynamic_load=false
force=false
no_static_build=false
rerun=false
skip_main_test=false
skip_shared=false
ip2location_versions_test=false

while getopts ":cbDNMirIfWn?h" opt; do
	case $opt in
	    'b')
		batch=true
		;;
	    'f')
		force=true
		;;
	    'r')
		rerun=true
		;;
	    'N')
		no_static_build=true
		;;
	    'n')
		dry_run=true
		;;
	    'M')
		skip_main_test=true
		;;
	    'I')
		skip_token="IP2LOCATION"
		;;
	    'i')
		ip2location_versions_test=true
		skip_shared=true
		no_static_build=true
		;;
	    'c')
		cross_versions_test=true
		;;
	    'D')
		dynamic_load=true
		;;
	    \?|h)
		help
		exit 1
		;;
	    *)
		echo "Invalid option: -$OPTARG" >&2
		exit 1
		;;
	esac
done

shift $[ $OPTIND - 1 ]

source ./autogen-support.sh "source"

if [ -n "$options_add" ]; then
	echo "INFO  : additional options: $options_add"
fi

if [ -f "$status_file" ] && ! $dry_run; then
	echo "INFO  : status file found: $status_file"

	if $force; then
		echo "NOTICE: remove status file (force)"
		rm $status_file
	else
		if grep -q ":END:" $status_file; then
			if $rerun; then
				echo "NOTICE: all runs successful, option -r given, status file removed (re-run)"
				rm $status_file
			else
				echo "NOTICE: all runs successful, nothing more to do (use -r for force a re-run)"
				exit 0
			fi
		else
			if $rerun; then
				echo "NOTICE: option -r for forcing a re-run is useless, last run was not finished (use -f)"
				exit 0
			fi
		fi
	fi
fi

if ! $dry_run; then
	if [ ! -f "$status_file" ]; then
		echo "INFO  : status file missing, create: $status_file"
		date "+%s:START:${batch:+BATCHMODE}" >$status_file
	fi
fi

IONICE="ionice -c 3"

if ! $IONICE true; then
	echo "NOTICE: disable use of ionice, not supported"
	IONICE=""
fi

# variants
for liboption in "normal" "shared"; do
	if $skip_shared  && [ "$liboption" = "shared" ]; then
		continue
	fi

	autogen_variants | while IFS="#" read token buildoptions testlist; do
		case "$OSTYPE" in
		    freebsd*)
			case $token in
			    BUNDLED)
				echo "NOTICE: disable on OSTYPE=$OSTYPE: $buildoptions"
				continue
				;;
			esac
		esac

		buildoptions=$(echo $buildoptions)
		if [ -n "$options_add" ]; then
			if $no_static_build; then
				options="--no-static-build $options_add $buildoptions"
			else
				options="${options_add:+$options_add }$buildoptions"
			fi
		else
			if $no_static_build; then
				options="--no-static-build $buildoptions"
			else
				options="$buildoptions"
			fi
		fi

		case $liboption in
		    shared)
			options="${options:+$options }-S"
			;;
		esac

		# extend options in fallback case
		if [ -n "$ip2location_options_extra" ]; then
			if echo "$token" | grep -Fwq "IP2LOCATION"; then
				options="${options:+$options }$ip2location_options_extra"
			fi
		fi

		# check for already executed option combination
		if [ -f "$status_file" ]; then
			if [ -z "$testlist" ]; then
				if grep -Eq ":FINISHED:variants:$options:" $status_file; then
					echo "NOTICE: skip variant run (already finished) with: $options"
					continue
				fi
			else
				echo "NOTICE: testlist not empty, check dedicated build (testlist: $testlist) with: $options"
			fi
		fi

		if [ -n "$skip_token" ]; then
			if echo "$token" | grep -Ewq "$skip_token"; then
				echo "NOTICE: skip variant because of token: $token"
				if $dry_run; then
					date "+%s:FINISHED:variants:$options:SKIPPED" >>$status_file
				fi
				continue
			fi
		fi

		options_test=""

		if [ -n "$testlist" ]; then
			options_test="--no-test"
		fi

		if $dry_run; then
			echo "INFO  : would call(dry-run): ./autogen.sh $options_test $options"
			if [ -z "$testlist" ]; then
				continue
			fi
		else
			# run autogen
			echo "INFO  : call: ./autogen.sh $options_test $options"

			nice -n 20 $IONICE ./autogen.sh $options_test $options
			if [ $? -ne 0 ]; then
				echo "ERROR : autogen.sh reports an error with options: $options_test $options"
				if $batch; then
					date "+%s:BROKEN:variants:$options" >>$status_file
				else
					exit 1
				fi
			else
				# add entry in log
				date "+%s:FINISHED:variants:$options:OK" >>$status_file
			fi
		fi

		if [ -n "$testlist" ]; then
			for entry in $testlist; do
				if grep -Eq ":FINISHED:variants:$options:TESTLIST-ENTRY=$entry" $status_file; then
					echo "NOTICE: skip variant test (already finished) with: $options and $entry"
					continue
				fi

				if $dry_run; then
					echo "INFO  : would call(dry-run): ./autogen.sh $options (testlist entry: $entry)"
					continue
				fi

				name=${entry/:*}
				version=${entry/*:}
				lib=$(options_from_name_version $name $version "only-lib")
				libdir=$(options_from_name_version $name $version "only-libdir")

				if [ -z "$lib" ]; then
					echo "ERROR : something wrong in call of: options_from_name_version $name $version 'only-lib'"
					exit 1
				fi

				if [ -z "$libdir" ]; then
					echo "ERROR : something wrong in call of: options_from_name_version $name $version 'only-libdir'"
					exit 1
				fi

				if [ ! -e "$lib" ]; then
					echo "ERROR : library missing: $lib (got from: options_from_name_version $name $version 'only-lib')"
					exit 1
				fi

				if [ ! -d "$libdir" ]; then
					echo "ERROR : library directory missing: $libdir (got from: options_from_name_version $name $version 'only-libdir')"
					exit 1
				fi

				if $dynamic_load; then
					case $name in
					    I*)
						feature_string="IP2Location"
						;;
					    G*)
						feature_string="GeoIP"
						;;
					esac

					# check for feature dynamic load
					echo "INFO  : call: LD_LIBRARY_PATH=$libdir ./ipv6calc/ipv6calc -v"
					if ! LD_LIBRARY_PATH="$libdir" ./ipv6calc/ipv6calc -v 2>&1 | grep version | grep -qw $feature_string; then
						echo "ERROR : call has not included required feature string '$feature_string': LD_LIBRARY_PATH=$libdir ./ipv6calc/ipv6calc -v"
						exit 1
					fi

					echo "INFO  : call: LD_LIBRARY_PATH=$libdir make test-ldlibpath"
					LD_LIBRARY_PATH="$libdir" $MAKE test-ldlibpath
					result=$?
				else
					echo "INFO  : call: LD_PRELOAD=$lib make test-ldlibpath"
					LD_LIBRARY_PATH="$libdir" $MAKE test-ldlibpath
					result=$?
				fi

				if [ $result -ne 0 ]; then
					echo "ERROR : autogen.sh reports an error with options: $options during testlist entry: $entry"
					if $dynamic_load; then
						echo "NOTICE: executed command: LD_LIBRARY_PATH=$libdir make test-ldlibpath"
					else
						echo "NOTICE: executed command: LD_PRELOAD="$lib" make test-ldlibpath"
					fi

					if $batch; then
						date "+%s:BROKEN:variants:$options:TESTLIST-ENTRY=$entry" >>$status_file
					else
						exit 1
					fi
				else
					date "+%s:FINISHED:variants:$options:TESTLIST-ENTRY=$entry" >>$status_file
				fi
			done
		fi

	done || exit 1
done


if ! $dry_run; then
	if grep -q ":BROKEN:" $status_file; then
		echo "ERROR : there are BROKEN builds:"
		grep ":BROKEN:" $status_file
		exit 1
	else
		echo "INFO  : congratulations, all variants built successful!"
	fi
	date "+%s:END:" >>$status_file
	cat $status_file

	$MAKE autoclean >/dev/null
	if [ $? -ne 0 ]; then
		echo "ERROR : 'make autoclean' failed"
		exit 1
	fi
fi

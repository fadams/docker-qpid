#!/bin/bash
#
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
# 
#   http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.
#

################################################################################
# Script to build compact Docker images for any version of qpid-cpp.
# This script will download the specified version of qpid-cpp, it will then
# identify the best Proton version for Qpid versions that support AMQP 1.0
# and build and install that prior to building qpid-cpp. After it has built
# qpid-cpp the script will identify all of the shared library dependencies 
# then package up the executable and library dependencies for export.
################################################################################

# Get the Qpid version to build from the command line
VERSION=$1

echo Downloading qpid-cpp-${VERSION}

# Given a Qpid version work out which path to fetch it from as that is
# different for trunk, >= 0.34 and < 0.34. Once fetched we extract, tidy up
# then make sure the path is /usr/src/qpid-cpp irrespective of the version.
if [ ${VERSION} = trunk ]; then
    # Fetch trunk
    echo cloning trunk
    git clone https://git-wip-us.apache.org/repos/asf/qpid-cpp.git
elif [ ${VERSION:0:2} == 0. ] && [ ${VERSION} != 0.34 ]; then
    # Fetch for version < 0.34
    echo fetching /dist/qpid/${VERSION}/qpid-cpp-${VERSION}.tar.gz
    curl -sSLO https://archive.apache.org/dist/qpid/${VERSION}/qpid-cpp-${VERSION}.tar.gz
    tar zxfp qpid-cpp-${VERSION}.tar.gz
    rm qpid-cpp-${VERSION}.tar.gz
    mv qpid* qpid-cpp
else
    # Fetch for version 0.34 and later
    echo fetching /dist/qpid/cpp/${VERSION}/qpid-cpp-${VERSION}.tar.gz
    curl -sSLO https://archive.apache.org/dist/qpid/cpp/${VERSION}/qpid-cpp-${VERSION}.tar.gz
    tar zxfp qpid-cpp-${VERSION}.tar.gz
    rm qpid-cpp-${VERSION}.tar.gz
    mv qpid* qpid-cpp
fi

# Try to figure out the header paths for ruby to avoid "missing ruby/config.h"
# errors when building older (0.16 and below) versions of Qpid
RUBYDIR=$(ruby -rrbconfig -e 'puts RbConfig::CONFIG["rubyhdrdir"]')
RUBYARCHDIR=$(ruby -rrbconfig -e 'puts RbConfig::CONFIG["rubyarchhdrdir"]')


FLAGS=""
USE_CMAKE=1

# Qpid versions 0.18 and below have a dependency on boost::system so we need
# to include libboost_system.a when building libqpidmessaging.a later.
ADDLIB_BOOST_SYSTEM_STATIC=""

# For old Qpid versions (less than 0.16) compiling with newer versions of gcc and
# boost cause a number of issues. The following applies patches to fix these.
if [ ${VERSION} = 0.5 ]  || [ ${VERSION} = 0.6 ]  || [ ${VERSION} = 0.8 ] ||
   [ ${VERSION} = 0.10 ] || [ ${VERSION} = 0.12 ] || [ ${VERSION} = 0.14 ]; then
    ADDLIB_BOOST_SYSTEM_STATIC="addlib /usr/lib/libboost_system.a\naddlib /usr/lib/libboost_filesystem.a\n"

    # For versions < 0.14 CMake builds seem to be a bit unreliable, so automake.
    if [ ${VERSION} != 0.14 ]; then
        USE_CMAKE=0
    fi

    # Older Qpid versions make use of state_saver.hpp and singleton.hpp but
    # otherwise work with boost 1.49.0 so copy those files from boost 1.34.1
    # Note that 0.18 and below fail on boost versions later than 1.49.0 as they
    # have dependencies on boost::filesystem V2
    curl -sSLO https://sourceforge.net/projects/boost/files/boost/1.34.1/boost_1_34_1.tar.gz
    tar zxfp boost_1_34_1.tar.gz
    rm boost_1_34_1.tar.gz

    cp boost_1_34_1/boost/state_saver.hpp /usr/include/boost/state_saver.hpp
    cp boost_1_34_1/boost/pool/detail/singleton.hpp /usr/include/boost/pool/detail/singleton.hpp

    cd qpid-cpp

    # The "using namespace boost;" line in FrameSet.cpp causes ambiguity for
    # uint64_t, so qualify it with ::
    sed -i "s/uint64_t/::uint64_t/g" src/qpid/framing/FrameSet.cpp

    # These files have missing headers that later gcc versions are picky about.
    echo -e "#include <stdint.h>\n$(cat src/qpid/sys/Shlib.h)" > src/qpid/sys/Shlib.h
    echo -e "#include <unistd.h>\n$(cat src/qpid/sys/posix/Socket.cpp)" > src/qpid/sys/posix/Socket.cpp
    echo -e "#include <unistd.h>\n$(cat src/qpid/sys/posix/SystemInfo.cpp)" > src/qpid/sys/posix/SystemInfo.cpp

    if [ ${VERSION} = 0.5 ] || [ ${VERSION} = 0.6 ] ||
       [ ${VERSION} = 0.8 ] || [ ${VERSION} = 0.10 ]; then
        sed -i "s/mutable FrameHandler/FrameHandler/g" src/qpid/framing/SendContent.h

        if [ ${VERSION} = 0.5 ] || [ ${VERSION} = 0.6 ]; then
            sed -i "s/#include <xqilla\/xqilla-simple.hpp>/#include <xqilla\/xqilla-simple.hpp>\n#include <xqilla\/ast\/XQEffectiveBooleanValue.hpp>/g" src/qpid/xml/XmlExchange.cpp

            sed -i "s/return result->getEffectiveBooleanValue(context.get(), 0);/Item::Ptr first_ = result->next(context.get());\nItem::Ptr second_ = result->next(context.get());\nreturn XQEffectiveBooleanValue::get(first_, second_, context.get(), 0);\n/g" src/qpid/xml/XmlExchange.cpp

            # 0.5 is old and sad and needs lots of patchy TLC on newer g++/boost
            if [ ${VERSION} = 0.5 ]; then
                sed -i "s/nspr4\///g" src/qpid/sys/ssl/check.h src/qpid/sys/ssl/SslSocket.cpp src/qpid/sys/ssl/util.cpp
                sed -i "s/nspr4\//nspr\//g" src/qpid/sys/ssl/SslSocket.h
                sed -i "s/nss3\///g" src/qpid/sys/ssl/check.h src/qpid/sys/ssl/check.cpp src/qpid/sys/ssl/SslSocket.cpp src/qpid/sys/ssl/util.cpp
            fi
        fi

        # -DBOOST_FILESYSTEM_VERSION=2 needed by 0.8 and below
        # -fpermissive -Wno-error=unused-but-set-variable needed by 0.10 and below
        FLAGS="-DBOOST_FILESYSTEM_VERSION=2 -fpermissive -Wno-error=unused-but-set-variable " 
    fi

    cd ..
    
    FLAGS+="-Wno-error=cast-qual -Wno-error=narrowing -I"${RUBYDIR}" -I"${RUBYDIR}"/x86_64-linux -I"${RUBYARCHDIR}

elif [ ${VERSION} = 0.16 ]; then
    ADDLIB_BOOST_SYSTEM_STATIC="addlib /usr/lib/libboost_system.a\naddlib /usr/lib/libboost_filesystem.a\n"
    # Qpid 0.16 builds without the patches above, but needs a few flags tweaking
    FLAGS="-Wno-error=narrowing -I"${RUBYDIR}" -I"${RUBYDIR}"/x86_64-linux -I"${RUBYARCHDIR}

elif [ ${VERSION} = 0.18 ] || [ ${VERSION} = 0.20 ]; then
    ADDLIB_BOOST_SYSTEM_STATIC="addlib /usr/lib/libboost_system.a\naddlib /usr/lib/libboost_filesystem.a\n"

elif [ ${VERSION} = 0.22 ] || [ ${VERSION} = 0.24 ]; then
    # make install fails for 0.22 and 0.24 if LICENSE is not present.
    cp LICENSE qpid-cpp/bindings/qpid/perl/.
fi


# Grok the amqp.cmake file if it exists to work out the best Proton version to
# use for Qpid versions that support AMQP 1.0
PROTON_VERSION=0
PROTON_PATH="proton-c/"
if [ ${VERSION} = trunk ]; then
    PROTON_VERSION="trunk"
elif test -f "qpid-cpp/src/amqp.cmake"; then
    if [ ${VERSION} = 0.20 ] || [ ${VERSION} = 0.22 ]; then
        PROTON_VERSION=0.3
        PROTON_PATH="./"
    else
        #grep "set (maximum_version" qpid-cpp/src/amqp.cmake
        PROTON_VERSION=$(grep -Po "(?<=set \(maximum_version )\d*\.?\d*" qpid-cpp/src/amqp.cmake)
    fi
fi

# Build Proton if Qpid version supports AMQP 1.0
ADDLIB_PROTON_STATIC=""
if [ ${PROTON_VERSION} != 0 ]; then
    # Some versions of Proton barf if these aren't installed.
    gem install rspec
    gem install simplecov

    echo Downloading qpid-proton-${PROTON_VERSION}

    if [ ${PROTON_VERSION} = trunk ]; then
        # Fetch trunk
        echo cloning trunk
        git clone https://git-wip-us.apache.org/repos/asf/qpid-proton.git
    elif [ ${PROTON_VERSION} = 0.1 ] || [ ${PROTON_VERSION} = 0.2 ] ||
         [ ${PROTON_VERSION} = 0.3 ]; then
        # Fetch for version < 0.4
        echo fetching /dist/qpid/proton/${PROTON_VERSION}/qpid-proton-c-${PROTON_VERSION}.tar.gz
        curl -sSLO https://archive.apache.org/dist/qpid/proton/${PROTON_VERSION}/qpid-proton-c-${PROTON_VERSION}.tar.gz
        tar zxfp qpid-proton-c-${PROTON_VERSION}.tar.gz
        rm qpid-proton-c-${PROTON_VERSION}.tar.gz
        mv qpid-proton* qpid-proton
    else
        # Fetch for version 0.4 and later
        if [ ${PROTON_VERSION} = 0.4 ] || [ ${PROTON_VERSION} = 0.5 ] ||
           [ ${PROTON_VERSION} = 0.6 ] || [ ${PROTON_VERSION} = 0.7 ] ||
           [ ${PROTON_VERSION} = 0.8 ] || [ ${PROTON_VERSION} = 0.9 ] ||
           [ ${PROTON_VERSION} = 0.10 ]; then
            #do nothing
            :
        else
            # Latest Proton version numbering scheme includes patch version.
            PROTON_VERSION+=".0"
        fi

        echo fetching /dist/qpid/proton/${PROTON_VERSION}/qpid-proton-${PROTON_VERSION}.tar.gz
        curl -sSLO https://archive.apache.org/dist/qpid/proton/${PROTON_VERSION}/qpid-proton-${PROTON_VERSION}.tar.gz
        tar zxfp qpid-proton-${PROTON_VERSION}.tar.gz
        rm qpid-proton-${PROTON_VERSION}.tar.gz
        mv qpid-proton* qpid-proton
    fi

    echo Building qpid-proton-${PROTON_VERSION}

    cd qpid-proton

    # Patch CMake file to build statically linked qpid-proton.
    sed -i "s/add_library/add_library (qpid-proton_static STATIC \${qpid-proton-core} \${qpid-proton-platform} \${qpid-proton-include})\n\nadd_library/g" ${PROTON_PATH}CMakeLists.txt

    mkdir build
    cd build
    cmake -DCMAKE_BUILD_TYPE=Release ..
    make -j$(getconf _NPROCESSORS_ONLN)
    make install
    cd ..
    cd ..

    ADDLIB_PROTON_STATIC="addlib /usr/src/qpid-proton/build/"${PROTON_PATH}"libqpid-proton_static.a\n"
fi

# Build Qpid cpp
echo Building qpid-cpp-${VERSION}

# Add -s flag to strip executables and libraries.
FLAGS+=" -s"

#echo ${FLAGS}

cd qpid-cpp
ADDLIB_QPIDMESSAGING_STATIC=""
# Version 0.5 to 0.12 require automake but everything later can use CMake.
# rpath is set explicitly to avoid run time link errors, this is actually fixed
# in 0.22 onwards, but setting it explicitly here doesn't hurt.
if [ ${USE_CMAKE} = 1 ]; then
    # Patch CMake file to build statically linked libqpidmessaging. This allows
    # clients to avoid having to install too many dependencies just to use Qpid
    # in particular avoiding boost dependency hell, which can be a real PITA.
    # 0.22 and below have an ssl.cmake later versions directly include required
    # files as part of qpidcommon_SOURCES and qpidclient_SOURCES
    if test -f "src/ssl.cmake"; then
        sed -i "s/add_msvc_version (qpidmessaging library dll)/add_msvc_version (qpidmessaging library dll)\nadd_library (qpidmessaging_static STATIC \${qpidmessaging_SOURCES} \${qpidtypes_SOURCES} \${qpidclient_SOURCES} \${qpidcommon_SOURCES} \${sslcommon_SOURCES} qpid\/client\/SslConnector.cpp)\ninclude_directories(\${NSS_INCLUDE_DIRS})\n/g" src/CMakeLists.txt
    else
        sed -i "s/add_msvc_version (qpidmessaging library dll)/add_msvc_version (qpidmessaging library dll)\nadd_library (qpidmessaging_static STATIC \${qpidmessaging_SOURCES} \${qpidtypes_SOURCES} \${qpidclient_SOURCES} \${qpidcommon_SOURCES})\n/g" src/CMakeLists.txt
    fi

    # Patch CMake file to add install for spout and drain binaries. This isn't
    # strictly necessary, but doing an install cases the library dependencies
    # to be /usr/local/lib rather than /usr/src/qpid-cpp/build/src
    echo -e "install (TARGETS spout RUNTIME DESTINATION \${QPID_INSTALL_SBINDIR})\ninstall (TARGETS drain RUNTIME DESTINATION \${QPID_INSTALL_SBINDIR})\n" >> examples/messaging/CMakeLists.txt

    mkdir build
    cd build
    cmake -DCMAKE_INSTALL_RPATH=/usr/local/lib -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_FLAGS="$FLAGS" ..
    make -j$(getconf _NPROCESSORS_ONLN)
    # Different CMake versions seem to name these differently, so create a copy
    # with the alternate name to keep make install happy for older Qpid versions.
    if test -f "bindings/qpid/ruby/cqpid_ruby.so"; then
        cp bindings/qpid/ruby/cqpid_ruby.so bindings/qpid/ruby/libcqpid_ruby.so
    fi
    if test -f "bindings/qmf/ruby/qmfengine_ruby.so"; then
        cp bindings/qmf/ruby/qmfengine_ruby.so bindings/qmf/ruby/libqmfengine_ruby.so
    fi
    if test -f "bindings/qmf2/ruby/cqmf2_ruby.so"; then
        cp bindings/qmf2/ruby/cqmf2_ruby.so bindings/qmf2/ruby/libcqmf2_ruby.so
    fi
    make install
    # Put the executables in /usr/bin in the docker image.
    cp /usr/local/sbin/qpidd /usr/bin/qpidd
    cp /usr/local/sbin/spout /usr/bin/spout
    cp /usr/local/sbin/drain /usr/bin/drain
    cd ..
    cd ..

    ADDLIB_QPIDMESSAGING_STATIC="addlib qpid-cpp/build/src/libqpidmessaging_static.a\n"
else
    ./configure --enable-static CXXFLAGS="$FLAGS" LDFLAGS=-Wl,-rpath,/usr/local/lib
    make -j$(getconf _NPROCESSORS_ONLN)
    make install
    # Put the executables in /usr/bin in the docker image.
    cp /usr/local/sbin/qpidd /usr/bin/qpidd
    # Qpid 0.5 doesn't have spout or drain
    if [ ${VERSION} != 0.5 ]; then
        cp examples/messaging/.libs/spout /usr/bin/spout
        cp examples/messaging/.libs/drain /usr/bin/drain
    fi
    cd ..

    # Qpid 0.6 has qpid::messaging but it's not API compatible with later version.
    if [ ${VERSION} = 0.5 ] || [ ${VERSION} = 0.6 ]; then
        ADDLIB_QPIDMESSAGING_STATIC=""
    else
        mv /usr/local/lib/libqpidmessaging.a /usr/local/lib/libqpidmessaging_static.a
        ADDLIB_QPIDMESSAGING_STATIC="addlib /usr/local/lib/libqpidmessaging_static.a\naddlib /usr/local/lib/libqpidtypes.a\naddlib /usr/local/lib/libqpidclient.a\naddlib /usr/local/lib/libqpidcommon.a\naddlib /usr/local/lib/libsslcommon.a\naddlib /usr/local/lib/qpid/client/sslconnector.a\n"
    fi
fi

# Display the version of the qpidd we've just built.
qpidd -v

################################################################################
# Identify the complete set of dependencies that will be used to create an
# archive of the executables and their dependencies which may be used to create
# Docker images containing only what is necessary to run the application.
################################################################################

################################################################################
# Build qpidd archive used to build Docker image.
################################################################################

# Use ldd to extract the library dependencies of qpidd using awk to parse the
# ldd output in order to print just the paths of the dependent libraries.
ldd /usr/bin/qpidd | awk '/=> \//{print $(NF-1)}' > qpidd-dep.txt

# Many of the loadable modules contain some additional dependencies use ldd
# to extract the correct full path of those dependencies too.
if test -f "/usr/local/lib/qpid/daemon/amqp.so"; then
    ldd /usr/local/lib/qpid/daemon/amqp.so | awk '/libqpid-proton/{print $(NF-1)}' >> qpidd-dep.txt
fi

if test -f "/usr/local/lib/qpid/daemon/ha.so"; then
    ldd /usr/local/lib/qpid/daemon/ha.so | awk '/libqpidclient|libqpidmessaging|libcrypto/{print $(NF-1)}' >> qpidd-dep.txt
fi

if test -f "/usr/local/lib/qpid/daemon/linearstore.so"; then
    ldd /usr/local/lib/qpid/daemon/linearstore.so | awk '/libaio|liblinearstoreutils|libdb_cxx/{print $(NF-1)}' >> qpidd-dep.txt
fi

if test -f "/usr/local/lib/qpid/daemon/rdma.so"; then
    ldd /usr/local/lib/qpid/daemon/rdma.so | awk '/librdmawrap|librdmacm|libibverbs/{print $(NF-1)}' >> qpidd-dep.txt
fi

if test -f "/usr/local/lib/qpid/daemon/xml.so"; then
    ldd /usr/local/lib/qpid/daemon/xml.so | awk '/libxerces-c|libxqilla|libnsl|libicui18n|libicuuc|libicudata/{print $(NF-1)}' >> qpidd-dep.txt
fi

ls -d -1 /usr/local/lib/qpid/daemon/*.so >> qpidd-dep.txt

# Extract the SASL plugin dependencies. Note that this is currently the basic
# set of authentication modules installed as dependencies of libsasl2-dev.
# It may be worth including all sasl2 pluggable modules and their dependencies
# in order to create the most general purpose Docker images.
ls -d -1 /usr/lib/x86_64-linux-gnu/sasl2/*.so >> qpidd-dep.txt
ldd /usr/lib/x86_64-linux-gnu/sasl2/libsasldb.so | awk '/libdb/{print $(NF-1)}' >> qpidd-dep.txt

echo "/usr/bin/qpidd" >> qpidd-dep.txt

# Use ldd to extract the Linux dynamic runtime loader, this is likely to be
# something like /lib64/ld-linux-x86-64.so.2
ldd /usr/bin/qpidd | awk 'NF==2 && /\//{print $(NF-1)}' >> qpidd-dep.txt

# Add the nss libraries necessary for supporting files (/etc/passwd, etc) and
# DNS for hostname lookups. See the following link for more information.
# http://blog.oddbit.com/2015/02/05/creating-minimal-docker-images/
echo "/lib/x86_64-linux-gnu/libnss_dns.so.2" >> qpidd-dep.txt
echo "/lib/x86_64-linux-gnu/libnss_files.so.2" >> qpidd-dep.txt

# Add various config files to the set of dependencies
if test -f "/usr/local/etc/qpid/qpidd.conf"; then
    ls -d -1 /usr/local/etc/qpid/qpidd.conf >> qpidd-dep.txt
else
    ls -d -1 /usr/local/etc/qpidd.conf >> qpidd-dep.txt
fi

ls -d -1 /usr/local/etc/sasl2/qpidd.conf >> qpidd-dep.txt

mv /etc/nsswitch.conf /etc/nsswitch.conf.bak
echo -e "passwd:     files\nshadow:     files\ngroup:      files\nhosts:      files dns\n" > /etc/nsswitch.conf

echo "/etc/nsswitch.conf" >> qpidd-dep.txt


# Create an archive for qpidd using the dependencies that we've just identified.
# The h option follows symlinks and archives the files they refer to, which is
# necessary in order to create a portable archive used to create a qpidd image.
tar hzcf qpidd.tar.gz -T qpidd-dep.txt

# Qpid 0.5 doesn't have spout, drain or libqpidmessaging
if [ ${VERSION} = 0.5 ]; then
    tar zcf qpid.tar.gz qpidd.tar.gz
else
    ############################################################################
    # Build spout archive used to build Docker image.
    ############################################################################

    # Use ldd to extract the library dependencies of spout using awk to parse the
    # ldd output in order to print just the paths of the dependent libraries.
    ldd /usr/bin/spout | awk '/=> \//{print $(NF-1)}' > spout-dep.txt

    # Extract the SASL plugin dependencies. Note that this is currently the basic
    # set of authentication modules installed as dependencies of libsasl2-dev.
    # It may be worth including all sasl2 pluggable modules and their dependencies
    # in order to create the most general purpose Docker images.
    ls -d -1 /usr/lib/x86_64-linux-gnu/sasl2/*.so >> spout-dep.txt
    ldd /usr/lib/x86_64-linux-gnu/sasl2/libsasldb.so | awk '/libdb-5.1/{print $(NF-1)}' >> spout-dep.txt

    echo "/usr/bin/spout" >> spout-dep.txt

    # Use ldd to extract the Linux dynamic runtime loader, this is likely to be
    # something like /lib64/ld-linux-x86-64.so.2
    ldd /usr/bin/spout | awk 'NF==2 && /\//{print $(NF-1)}' >> spout-dep.txt

    # Add the nss libraries necessary for supporting files (/etc/passwd, etc) and
    # DNS for hostname lookups. See the following link for more information.
    # http://blog.oddbit.com/2015/02/05/creating-minimal-docker-images/
    echo "/lib/x86_64-linux-gnu/libnss_dns.so.2" >> spout-dep.txt
    echo "/lib/x86_64-linux-gnu/libnss_files.so.2" >> spout-dep.txt

    # Add various config files to the set of dependencies
    echo "/etc/nsswitch.conf" >> spout-dep.txt

    # Create an archive for spout using the dependencies that we've just identified.
    # The h option follows symlinks and archives the files they refer to, which is
    # necessary in order to create a portable archive used to create a spout image.
    tar hzcf spout.tar.gz -T spout-dep.txt

    ############################################################################
    # Build drain archive used to build Docker image.
    ############################################################################

    # Use ldd to extract the library dependencies of drain using awk to parse the
    # ldd output in order to print just the paths of the dependent libraries.
    ldd /usr/bin/drain | awk '/=> \//{print $(NF-1)}' > drain-dep.txt

    # Extract the SASL plugin dependencies. Note that this is currently the basic
    # set of authentication modules installed as dependencies of libsasl2-dev.
    # It may be worth including all sasl2 pluggable modules and their dependencies
    # in order to create the most general purpose Docker images.
    ls -d -1 /usr/lib/x86_64-linux-gnu/sasl2/*.so >> drain-dep.txt
    ldd /usr/lib/x86_64-linux-gnu/sasl2/libsasldb.so | awk '/libdb-5.1/{print $(NF-1)}' >> drain-dep.txt

    echo "/usr/bin/drain" >> drain-dep.txt

    # Use ldd to extract the Linux dynamic runtime loader, this is likely to be
    # something like /lib64/ld-linux-x86-64.so.2
    ldd /usr/bin/drain | awk 'NF==2 && /\//{print $(NF-1)}' >> drain-dep.txt

    # Add the nss libraries necessary for supporting files (/etc/passwd, etc) and
    # DNS for hostname lookups. See the following link for more information.
    # http://blog.oddbit.com/2015/02/05/creating-minimal-docker-images/
    echo "/lib/x86_64-linux-gnu/libnss_dns.so.2" >> drain-dep.txt
    echo "/lib/x86_64-linux-gnu/libnss_files.so.2" >> drain-dep.txt

    # Add various config files to the set of dependencies
    echo "/etc/nsswitch.conf" >> drain-dep.txt

    # Create an archive for drain using the dependencies that we've just identified.
    # The h option follows symlinks and archives the files they refer to, which is
    # necessary in order to create a portable archive used to create a drain image.
    tar hzcf drain.tar.gz -T drain-dep.txt

    ############################################################################
    # Build qpid::messaging static library and includes archive. This allows
    # clients to avoid having to install too many dependencies just to use Qpid,
    # in particular avoiding boost dependency hell, which can be a real PITA.
    ############################################################################

    # In Qpid 0.6 the qpid::messaging API was in development and unlikely to
    # work with clients using the final API, so it's not worth exporting.
    if [ ${VERSION} = 0.6 ]; then
        # Build archive that contains qpidd, spout and drain
        tar zcf qpid.tar.gz qpidd.tar.gz spout.tar.gz drain.tar.gz
    else
        # Use MRI script to create an archive that merges the contents of other
        # libs. https://sourceware.org/binutils/docs/binutils/ar-scripts.html
        echo -e "create /usr/local/lib/libqpidmessaging.a\n" \
                $ADDLIB_QPIDMESSAGING_STATIC \
                $ADDLIB_PROTON_STATIC \
                "addlib /usr/lib/libboost_program_options.a\n" \
                $ADDLIB_BOOST_SYSTEM_STATIC \
                "save\n" \
                "end\n" | ar -M

        TCPConnector=$(ar t /usr/local/lib/libqpidmessaging.a | grep TCPConnector)
        SSLConnector=$(ar t /usr/local/lib/libqpidmessaging.a | grep SslConnector)
        Statement=$(ar t /usr/local/lib/libqpidmessaging.a | grep Statement)

        ar x /usr/local/lib/libqpidmessaging.a $TCPConnector
        ar x /usr/local/lib/libqpidmessaging.a $SSLConnector
        ar x /usr/local/lib/libqpidmessaging.a $Statement
        ar d /usr/local/lib/libqpidmessaging.a $TCPConnector
        ar d /usr/local/lib/libqpidmessaging.a $SSLConnector
        ar d /usr/local/lib/libqpidmessaging.a $Statement

        ld -r $Statement $TCPConnector $SSLConnector -o /usr/local/lib/libqpidinit.a

        ranlib /usr/local/lib/libqpidmessaging.a

        # TODO limit the include files included in the archive.
        tar zcf messaging.tar.gz -C /usr/local lib/libqpidmessaging.a lib/libqpidinit.a include/qpid

        # Build archive that contains qpidd, spout, drain and qpid::messaging
        tar zcf qpid.tar.gz qpidd.tar.gz spout.tar.gz drain.tar.gz messaging.tar.gz
    fi
fi

echo Finished building qpid-cpp-${VERSION}


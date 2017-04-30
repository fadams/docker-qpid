# qpid-cpp

Dockerised build for [Apache Qpid](http://qpid.apache.org/) [C++ Broker](http://qpid.apache.org/components/cpp-broker/index.html) and the Qpid [Messaging API](http://qpid.apache.org/components/messaging-api/index.html) C++ bindings.

Two different build system Dockerfiles are included, the first is based on *debian:wheezy-slim* and the second on *debian:jessie-slim*. The former is somewhat more straightforward as it simply uses the default gcc, g++ and libboost-all-dev packages from debian wheezy (gcc 4.7.2 and boost 1.49.0). Using debian jessie is, however, a little more involved as although the most recent versions of Qpid compile fine on gcc 4.9 and boost 1.55 earlier versions only reliably compile with versions as high as gcc 4.7.2 and boost 1.49.0. The Dockerfile for the debian:jessie-slim based build system therefore downloads, builds and installs gcc 4.7.2 and boost 1.49.0 as part of building the image, which can take some time.

To build the Qpid build toolchain based on debian:wheezy-slim:
```
docker build -t build-qpid-cpp:wheezy -f Dockerfile.build-qpid-cpp.wheezy .
```

To build the Qpid build toolchain based on debian:jessie-slim:
```
docker build -t build-qpid-cpp:jessie -f Dockerfile.build-qpid-cpp.jessie .
```

Having built a build toolchain image it is then possible to build any released version of qpid-cpp from 0.5 to trunk as the build script has included the necessary tweaks and patches required to successfully build older Qpid versions. The build system exports a gzipped tar file *qpid.tar.gz* which contains qpidd.tar.gz spout.tar.gz drain.tar.gz representing the files needed to create Docker images for qpidd, spout and drain plus messaging.tar.gz which contains headers and **static** libraries for the qpid::messaging API for the specified version. Building and exporting a static library version of qpid::messaging is useful because it's fairly common to run into issues as a result of boost incompatibilities between the boost version needed by Qpid and that required/desired by the application using qpid::messaging.

Some examples of building specified Qpid versions using the debian:wheezy based toolchain:

**Qpid 0.5**
```
docker run --rm build-qpid-cpp:wheezy sh -c './build.sh 0.5 1>&2; tar c qpid.tar.gz' | tar xv
```
**Qpid 0.16**
```
docker run --rm build-qpid-cpp:wheezy sh -c './build.sh 0.16 1>&2; tar c qpid.tar.gz' | tar xv
```
**Qpid 0.32**
```
docker run --rm build-qpid-cpp:wheezy sh -c './build.sh 0.32 1>&2; tar c qpid.tar.gz' | tar xv
```
**Qpid 1.36.0**
```
docker run --rm build-qpid-cpp:wheezy sh -c './build.sh 1.36.0 1>&2; tar c qpid.tar.gz' | tar xv
```
**Qpid trunk**
```
docker run --rm build-qpid-cpp:wheezy sh -c './build.sh trunk 1>&2; tar c qpid.tar.gz' | tar xv
```


&nbsp;


Similarly to build the same specified Qpid versions using the debian:jessie based toolchain:

**Qpid 0.5**
```
docker run --rm build-qpid-cpp:jessie sh -c './build.sh 0.5 1>&2; tar c qpid.tar.gz' | tar xv
```
**Qpid 0.16**
```
docker run --rm build-qpid-cpp:jessie sh -c './build.sh 0.16 1>&2; tar c qpid.tar.gz' | tar xv
```
**Qpid 0.32**
```
docker run --rm build-qpid-cpp:jessie sh -c './build.sh 0.32 1>&2; tar c qpid.tar.gz' | tar xv
```
**Qpid 1.36.0**
```
docker run --rm build-qpid-cpp:jessie sh -c './build.sh 1.36.0 1>&2; tar c qpid.tar.gz' | tar xv
```
**Qpid trunk**
```
docker run --rm build-qpid-cpp:jessie sh -c './build.sh trunk 1>&2; tar c qpid.tar.gz' | tar xv
```


&nbsp;


The build systems make use of the *build.sh* script, which does the bulk of the work, and the commands above run build.sh passing in the required Qpid version redirecting stdout to stderr (the 1>&2 bit) this is done because in order to export the qpid.tar.gz created by the image we push that to stdout via tar c qpid.tar.gz then pipe it to tar xv.

Having exported qpid.tar.gz we untar it into its component parts:
```
tar xvfp qpid.tar.gz
```
And we are then able to build Docker images for the exported components:

**qpidd**
```
docker build -t qpidd -f Dockerfile.qpidd .
```
**spout**
```
docker build -t spout -f Dockerfile.spout .
```
**drain**
```
docker build -t drain -f Dockerfile.drain .
```

To display the version of the Dockerised qpidd:
```
docker run --rm qpidd -v
```

To run the Dockerised qpidd with port 5672 exported and no authentication:
```
docker run --rm -p 5672:5672 qpidd --auth no
```

**TODO** It should be possible to include authentication configuration via the qpidd --config and/or --sasl-config options along with mounting the relevant directory as a Docker volume as all of the main SASL plugins have been included in the qpidd image, but I've not yet tried it out.

Note that the images created by this toolchain are considerably smaller than the Qpid images on Dockerhub as they have been built as *microcontainers* following a similar approach to that described in this blog http://blog.oddbit.com/2015/02/05/creating-minimal-docker-images/.


In order to use the qpid::messaging static library first untar into an appropriate directory for your client application:
```
tar zxvfp messaging.tar.gz
```
This will create an *include* and *lib* directory.

In order to link it is necessary to use the following libraries:
```
-lqpidinit -lqpidmessaging -ldl -luuid -lsasl2 -lnss3 -lnspr4 -lplc4 -lssl3
```

The -lqpidinit is a little odd and represents TCPConnector.o SslConnector.o and Statement.o which contain static initialiser blocks or non-exported global variables which must be explicitly linked, see https://issues.apache.org/jira/browse/QPID-2259, http://grokbase.com/t/qpid/users/1121dkf18h/unknown-protocol-tcp and http://qpid.2158936.n2.nabble.com/compiling-statically-qpid-td7029304.html. The remainder of the libraries are (non-Qpid) dynamic libraries on which libqpidmessaging itself depends.

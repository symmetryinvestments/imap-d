#!/bin/bash

set -euxo pipefail

# Install dependency packages.
apt install -y libssl-dev

# Fetch the version 1.1.1g of the OpenSSL source.
wget https://github.com/openssl/openssl/archive/OpenSSL_1_1_1g.tar.gz
tar xzf OpenSSL_1_1_1g.tar.gz

# Build and install it under /usr/local/openssl.
pushd openssl-OpenSSL_1_1_1g
./config --prefix=/usr/local/openssl --openssldir=/usr/local/openssl shared zlib
make
make install
popd

# Create a package config file which points to our new installation.
cat > libssl.pc << EOF
prefix=/usr/local/openssl
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
sharedlibdir=\${libdir}
includedir=\${prefix}/include

Name: OpenSSL-libssl
Description: Secure Sockets Layer and cryptography libraries
Version: 1.1.1
Requires.private: libcrypto
Libs: -L\${libdir} -L\${sharedlibdir} -lssl
Cflags: -I\${includedir}
EOF

# Install it manually.
mv libssl.pc /usr/lib/x86_64-linux-gnu/pkgconfig/libssl.pc


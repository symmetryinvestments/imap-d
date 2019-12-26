#!/bin/bash

set -euxo pipefail
git clone https://github.com/openssl/openssl
pushd openssl
./config --prefix=/usr/local/openssl --openssldir=/usr/local/openssl shared zlib
make
sudo make install
popd
cat > libssl.pc << EOF
prefix=/usr/local/openssl
exec_prefix=${prefix}
libdir=${exec_prefix}/lib
sharedlibdir=${libdir}
includedir=${prefix}/include

Name: OpenSSL-libssl
Description: Secure Sockets Layer and cryptography libraries
Version: 1.1.1
Requires.private: libcrypto
Libs: -L${libdir} -L${sharedlibdir} -lssl
Cflags: -I${includedir}
EOF
sudo mv libssl.pc /usr/lib/x86_64-linux-gnu/pkgconfig/libssl.pc


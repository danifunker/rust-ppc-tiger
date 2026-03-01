#!/bin/bash
# Build curl with mbedTLS for PowerPC Mac OS X Tiger
# This enables git to use HTTPS with TLS 1.2!

set -e

CURL_VERSION="7.88.1"  # Last version with good PowerPC support
MBEDTLS_DIR="$HOME/mbedtls-2.28.8"
PREFIX="/usr/local"

echo "=== Building curl $CURL_VERSION with mbedTLS for Tiger ==="

# Check for mbedTLS
if [ ! -d "$MBEDTLS_DIR/library" ]; then
    echo "ERROR: mbedTLS not found at $MBEDTLS_DIR"
    echo ""
    echo "Build mbedTLS first:"
    echo "  cd mbedtls-2.28.8/library"
    echo "  gcc -arch ppc -std=c99 -O2 -mcpu=7450 -I../include -c *.c"
    echo "  ar rcs libmbedcrypto.a \$(ls *.o | grep -v '^ssl' | grep -v '^x509' | grep -v '^net_sockets')"
    echo "  ar rcs libmbedx509.a x509*.o"
    echo "  ar rcs libmbedtls.a ssl*.o debug.o net_sockets.o"
    exit 1
fi

# Download curl if needed
if [ ! -d "curl-$CURL_VERSION" ]; then
    echo "Downloading curl $CURL_VERSION..."
    if [ -x /usr/local/bin/wget ]; then
        /usr/local/bin/wget -O curl.tar.gz "https://curl.se/download/curl-$CURL_VERSION.tar.gz"
    elif [ -x /opt/local/bin/curl ]; then
        /opt/local/bin/curl -L -o curl.tar.gz "https://curl.se/download/curl-$CURL_VERSION.tar.gz"
    elif [ -x ./wget ]; then
        ./wget -O curl.tar.gz "https://curl.se/download/curl-$CURL_VERSION.tar.gz"
    else
        echo "ERROR: No download tool with TLS support found"
        exit 1
    fi
    tar xzf curl.tar.gz
fi

cd "curl-$CURL_VERSION"

export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig

# Configure for PowerPC Tiger with mbedTLS
echo "Configuring curl..."
./configure \
    --host=powerpc-apple-darwin8 \
    --prefix=/usr/local \
    --with-mbedtls="$MBEDTLS_DIR" \
    --without-gnutls \
    --without-nss \
    --without-libssh2 \
    --without-nghttp2 \
    --without-brotli \
    --without-zstd \
    --disable-http2 \
    --disable-ldap \
    --disable-ldaps \
    --disable-rtsp \
    --disable-dict \
    --disable-telnet \
    --disable-tftp \
    --disable-pop3 \
    --disable-imap \
    --disable-smb \
    --disable-smtp \
    --disable-gopher \
    --disable-mqtt \
    CC="gcc -arch ppc" \
    CPPFLAGS="-I$MBEDTLS_DIR/include" \
    CFLAGS="-O2 -mcpu=7450" \
    LDFLAGS="-L$MBEDTLS_DIR/library" \
    LIBS="-lmbedtls -lmbedx509 -lmbedcrypto"

# Fix src/Makefile - bypass libtool using static libcurl directly
# Libtool picks the wrong dylib on Tiger, so link against .libs/libcurl.a
echo "Patching src/Makefile to fix libtool linking..."
sed -i.bak "s|curl_LDADD = .*|curl_LDADD = $(pwd)/lib/.libs/libcurl.a -L$MBEDTLS_DIR/library -lmbedtls -lmbedx509 -lmbedcrypto -lz|" src/Makefile

echo "Building curl..."
make -C lib
make -C src

echo "Installing curl..."
sudo make -C lib install
sudo make -C src install

# Install CA bundle (Tiger has none)
echo "Installing CA certificate bundle..."
sudo mkdir -p /usr/local/share/curl
if [ -x /usr/local/bin/curl ]; then
    /usr/local/bin/curl -k https://curl.se/ca/cacert.pem -o /tmp/cacert.pem
    sudo cp /tmp/cacert.pem /usr/local/share/curl/cacert.pem
elif [ -x /opt/local/bin/curl ]; then
    /opt/local/bin/curl -L -o /tmp/cacert.pem https://curl.se/ca/cacert.pem
    sudo cp /tmp/cacert.pem /usr/local/share/curl/cacert.pem
else
    echo "WARNING: Could not download CA bundle. You may need to manually install it."
    echo "  Download https://curl.se/ca/cacert.pem to /usr/local/share/curl/cacert.pem"
fi

# Add CA bundle env var to profile if not already there
if ! grep -q CURL_CA_BUNDLE ~/.profile 2>/dev/null; then
    echo 'export CURL_CA_BUNDLE=/usr/local/share/curl/cacert.pem' >> ~/.profile
    echo "Added CURL_CA_BUNDLE to ~/.profile"
fi

echo ""
echo "=== curl with mbedTLS installed! ==="
echo ""
echo "Test with:"
echo "  /usr/local/bin/curl --version"
echo "  /usr/local/bin/curl https://github.com"
echo ""
echo "For git to use it, add to ~/.gitconfig:"
echo "  [http]"
echo "      sslBackend = mbedtls"
echo ""
echo "Or set GIT_CURL_PATH:"
echo "  export GIT_CURL_PATH=/usr/local/bin/curl"

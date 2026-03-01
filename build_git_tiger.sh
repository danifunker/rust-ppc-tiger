#!/bin/bash
# Build Git with HTTPS support for PowerPC Mac OS X Tiger
# Requires GNU make (from MacPorts: sudo port install gmake)

set -e

GIT_VERSION="2.43.0"
PREFIX="/usr/local"

echo "=== Building Git $GIT_VERSION with HTTPS for Tiger ==="

# Check for GNU make (system make 3.80 is too old)
GMAKE=""
if [ -x /opt/local/libexec/gnubin/make ]; then
    GMAKE=/opt/local/libexec/gnubin/make
elif [ -x /opt/local/bin/gmake ]; then
    GMAKE=/opt/local/bin/gmake
else
    echo "ERROR: GNU make not found"
    echo "Install with: sudo port install gmake"
    exit 1
fi
echo "Using GNU make: $GMAKE"

# Check for download tool
DOWNLOAD=""
if [ -x /usr/local/bin/wget ]; then
    DOWNLOAD="/usr/local/bin/wget -O"
elif [ -x /opt/local/bin/curl ]; then
    DOWNLOAD="/opt/local/bin/curl -L -o"
elif [ -x /usr/local/bin/curl ]; then
    DOWNLOAD="/usr/local/bin/curl -L -o"
else
    echo "ERROR: No download tool with TLS support found"
    exit 1
fi
echo "Using: $DOWNLOAD"

# Check for curl-config (needed for HTTPS clone/push)
if [ -x /usr/local/bin/curl-config ]; then
    CURL_CFG=/usr/local/bin/curl-config
elif [ -x /opt/local/bin/curl-config ]; then
    CURL_CFG=/opt/local/bin/curl-config
else
    echo "WARNING: curl-config not found — git will be built without HTTPS support"
    CURL_CFG=""
fi

# Create build directory
mkdir -p ~/git_build
cd ~/git_build

# Download Git
if [ ! -f "git-$GIT_VERSION.tar.gz" ]; then
    echo "Downloading Git $GIT_VERSION..."
    $DOWNLOAD git-$GIT_VERSION.tar.gz \
        "https://mirrors.edge.kernel.org/pub/software/scm/git/git-$GIT_VERSION.tar.gz"
fi

if [ ! -d "git-$GIT_VERSION" ]; then
    echo "Extracting Git..."
    tar xzf git-$GIT_VERSION.tar.gz
fi

cd git-$GIT_VERSION

# Configure (--without-openssl prevents MacPorts OpenSSL from leaking into link flags)
echo "Configuring Git..."
$GMAKE configure
./configure \
    --prefix=$PREFIX \
    --without-openssl \
    --without-tcltk \
    CC="gcc -arch ppc" \
    CFLAGS="-O2 -mcpu=7450 -std=c99" \
    LDFLAGS="-L/usr/local/lib -L/usr/lib" \
    CPPFLAGS="-I/usr/local/include" \
    PKG_CONFIG_PATH=/usr/local/lib/pkgconfig \
    ac_cv_lib_curl_curl_global_init=yes

# Create arc4random compat shim (not available on Tiger)
echo "Creating arc4random compatibility shim..."
cat > compat/arc4random.c << 'EOF'
#include <stdlib.h>
#include <string.h>
void arc4random_buf(void *buf, size_t n) {
    unsigned char *p = buf;
    for (size_t i = 0; i < n; i++)
        p[i] = rand() & 0xff;
}
EOF

# Common make flags for git on Tiger
MAKE_FLAGS=(
    CFLAGS="-O2 -mcpu=7450 -std=c99 -I/opt/local/include"
    LDFLAGS="-L/usr/local/lib -L/usr/lib"
    NO_FUZZER=1
    NO_REGEX=1
    BLK_SHA1=1
    USE_CURL_FOR_IMAP_SEND=YesPlease
    FSMONITOR_DAEMON_BACKEND=
    FSMONITOR_OS_SETTINGS=
    NEEDS_LIBICONV=YesPlease
    IMAP_SEND_LDFLAGS="-L/usr/local/lib -lcurl -lmbedtls -lmbedx509 -lmbedcrypto -lz"
    COMPAT_OBJS="compat/arc4random.o compat/fopen.o compat/memmem.o compat/qsort_s.o compat/precompose_utf8.o compat/stub/procinfo.o"
    EXTLIBS="compat/arc4random.o compat/fopen.o compat/memmem.o compat/qsort_s.o compat/precompose_utf8.o compat/stub/procinfo.o compat/regex/regex.o /usr/local/lib/libcurl.a /usr/local/lib/libmbedtls.a /usr/local/lib/libmbedx509.a /usr/local/lib/libmbedcrypto.a /opt/local/lib/libz.a -liconv"
)

if [ -n "$CURL_CFG" ]; then
    MAKE_FLAGS+=(CURL_CONFIG="$CURL_CFG")
fi

echo "Building Git..."
$GMAKE -j4 "${MAKE_FLAGS[@]}"

echo "Installing Git..."
sudo $GMAKE install "${MAKE_FLAGS[@]}"

# Configure SSL CA bundle for HTTPS
$PREFIX/bin/git config --global http.sslCAInfo /usr/local/share/curl/cacert.pem

echo ""
echo "=== Git $GIT_VERSION installed! ==="
echo ""
echo "Test with:"
echo "  $PREFIX/bin/git --version"
echo "  $PREFIX/bin/git ls-remote https://github.com/Scottcjn/pocketfox.git"
echo ""
echo "Configure Git:"
echo "  $PREFIX/bin/git config --global user.name 'Your Name'"
echo "  $PREFIX/bin/git config --global user.email 'you@example.com'"
echo ""
echo "Clone a repo:"
echo "  $PREFIX/bin/git clone https://github.com/Scottcjn/pocketfox.git"
echo ""
echo "Push with credentials:"
echo "  $PREFIX/bin/git push https://USER:TOKEN@github.com/USER/REPO.git"
echo ""

#!/bin/bash
# Build modern OpenSSH for PowerPC Mac OS X Tiger
# Uses LibreSSL for crypto (better than ancient system OpenSSL)

set -e

LIBRESSL_VERSION="3.3.6"
OPENSSH_VERSION="9.6p1"
PREFIX="/usr/local"

echo "=== Building OpenSSH $OPENSSH_VERSION with LibreSSL $LIBRESSL_VERSION for Tiger ==="

# Check for download tool (wget or curl with TLS)
DOWNLOAD=""
if [ -x /usr/local/bin/wget ]; then
    DOWNLOAD="/usr/local/bin/wget -O"
elif [ -x /opt/local/bin/curl ]; then
    DOWNLOAD="/opt/local/bin/curl -L -o"
elif [ -x /usr/local/bin/curl ]; then
    DOWNLOAD="/usr/local/bin/curl -L -o"
else
    echo "ERROR: No download tool with TLS support found"
    echo "Install MacPorts curl or build wget_tiger"
    exit 1
fi
echo "Using download tool: $DOWNLOAD"

# Create build directory
mkdir -p ~/openssh_build
cd ~/openssh_build

# ============================================
# Step 1: Build LibreSSL
# ============================================
echo ""
echo "=== Step 1: Building LibreSSL $LIBRESSL_VERSION ==="

if [ ! -f "libressl-$LIBRESSL_VERSION.tar.gz" ]; then
    echo "Downloading LibreSSL..."
    $DOWNLOAD libressl-$LIBRESSL_VERSION.tar.gz \
        "https://ftp.openbsd.org/pub/OpenBSD/LibreSSL/libressl-$LIBRESSL_VERSION.tar.gz"
fi

if [ ! -d "libressl-$LIBRESSL_VERSION" ]; then
    echo "Extracting LibreSSL..."
    tar xzf libressl-$LIBRESSL_VERSION.tar.gz
fi

cd libressl-$LIBRESSL_VERSION

if [ ! -f "$PREFIX/lib/libssl.a" ]; then
    echo "Configuring LibreSSL..."
    ./configure \
        --prefix=$PREFIX \
        --disable-shared \
        --enable-static \
        --host=powerpc-apple-darwin8 \
        CC="gcc -arch ppc" \
        CFLAGS="-arch ppc -O2 -mcpu=7450"

    echo "Building LibreSSL..."
    make -j2

    echo "Installing LibreSSL..."
    sudo make install
else
    echo "LibreSSL already installed, skipping..."
fi

cd ~/openssh_build

# ============================================
# Step 2: Build OpenSSH
# ============================================
echo ""
echo "=== Step 2: Building OpenSSH $OPENSSH_VERSION ==="

if [ ! -f "openssh-$OPENSSH_VERSION.tar.gz" ]; then
    echo "Downloading OpenSSH..."
    $DOWNLOAD openssh-$OPENSSH_VERSION.tar.gz \
        "https://cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/openssh-$OPENSSH_VERSION.tar.gz"
fi

if [ ! -d "openssh-$OPENSSH_VERSION" ]; then
    echo "Extracting OpenSSH..."
    tar xzf openssh-$OPENSSH_VERSION.tar.gz
fi

cd openssh-$OPENSSH_VERSION

# Create privilege separation directory and user if needed
if [ ! -d /var/empty ]; then
    echo "Creating /var/empty for privilege separation..."
    sudo mkdir -p /var/empty
    sudo chmod 755 /var/empty
fi

# Check for sshd user (Tiger may not have it)
if ! dscl . -read /Users/sshd > /dev/null 2>&1; then
    echo "Creating sshd user..."
    sudo dscl . -create /Users/sshd
    sudo dscl . -create /Users/sshd UserShell /usr/bin/false
    sudo dscl . -create /Users/sshd UniqueID 75
    sudo dscl . -create /Users/sshd PrimaryGroupID 75
    sudo dscl . -create /Users/sshd NFSHomeDirectory /var/empty
fi

# Rename system openssl to prevent version conflict during build
if [ -f /usr/bin/openssl ] && [ ! -f /usr/bin/openssl.tiger ]; then
    echo "Renaming system /usr/bin/openssl to prevent version conflict..."
    sudo mv /usr/bin/openssl /usr/bin/openssl.tiger
fi

echo "Configuring OpenSSH..."
./configure \
    --prefix=/usr/local \
    --sysconfdir=/etc/ssh \
    --with-ssl-dir=/usr/local \
    --with-privsep-path=/var/empty \
    --with-privsep-user=sshd \
    --with-zlib \
    --without-openssl-header-check \
    CC="gcc -arch ppc" \
    CPPFLAGS="-I/usr/local/include" \
    CFLAGS="-O2 -mcpu=7450 -I/usr/local/include" \
    LDFLAGS="-L/usr/local/lib -Wl,-search_paths_first"

echo "Building OpenSSH..."
make -j2

echo "Installing OpenSSH..."
sudo make install

# Restore system openssl if we renamed it
if [ -f /usr/bin/openssl.tiger ] && [ ! -f /usr/bin/openssl ]; then
    echo "Restoring system /usr/bin/openssl..."
    sudo mv /usr/bin/openssl.tiger /usr/bin/openssl
fi

# ============================================
# Step 3: Setup
# ============================================
echo ""
echo "=== Step 3: Setup ==="

# Generate host keys if needed
if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
    echo "Generating host keys..."
    sudo $PREFIX/bin/ssh-keygen -A
fi

echo ""
echo "=== OpenSSH $OPENSSH_VERSION installed successfully! ==="
echo ""
echo "New binaries installed to $PREFIX/bin and $PREFIX/sbin:"
echo "  $PREFIX/bin/ssh"
echo "  $PREFIX/bin/scp"
echo "  $PREFIX/bin/sftp"
echo "  $PREFIX/bin/ssh-keygen"
echo "  $PREFIX/sbin/sshd"
echo ""
echo "To use new SSH by default, add to ~/.profile:"
echo "  export PATH=$PREFIX/bin:$PREFIX/sbin:\$PATH"
echo ""
echo "To replace system SSH (CAREFUL!):"
echo "  sudo mv /usr/bin/ssh /usr/bin/ssh.tiger"
echo "  sudo ln -s $PREFIX/bin/ssh /usr/bin/ssh"
echo ""
echo "Test with:"
echo "  $PREFIX/bin/ssh -V"

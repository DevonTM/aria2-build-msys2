#!bash
case $MSYSTEM in
MINGW32)
    export MINGW_PACKAGE_PREFIX=mingw-w64-i686
    export HOST=i686-w64-mingw32
    ;;
MINGW64)
    export MINGW_PACKAGE_PREFIX=mingw-w64-x86_64
    export HOST=x86_64-w64-mingw32
    ;;
esac

# workaround git user name and email not set
GIT_USER_NAME="$(git config --global user.name)"
GIT_USER_EMAIL="$(git config --global user.email)"
if [[ "${GIT_USER_NAME}" = "" ]]; then
    git config --global user.name "Name"
fi
if [[ "${GIT_USER_EMAIL}" = "" ]]; then
    git config --global user.email "you@example.com"
fi

pacman -S --noconfirm --needed \
    $MINGW_PACKAGE_PREFIX-gcc \
    $MINGW_PACKAGE_PREFIX-cmake

PREFIX=/usr/local/$HOST
CPUCOUNT=$(nproc)
curl_opts=(/usr/bin/curl --connect-timeout 15 --retry 3
    --retry-delay 5 --silent --location --fail)

clean_html_index() {
    local url="$1"
    local filter="${2:-(?<=href=\")[^\"]+\.(tar\.(gz|bz2|xz)|7z)}"
    "${curl_opts[@]}" -l "$url" | grep -ioP "$filter" | sort -uV
}

clean_html_index_sqlite() {
    local url="$1"
    local filter="${2:-(\d+\/sqlite-autoconf-\d+\.tar\.gz)}"
    "${curl_opts[@]}" -l "$url" | grep -ioP "$filter" | sort -uV | tail -1
}

get_last_version() {
    local filelist="$1"
    local filter="$2"
    local version="$3"
    local ret
    ret="$(echo "$filelist" | /usr/bin/grep -E "$filter" | sort -V | tail -1)"
    [[ -n "$version" ]] && ret="$(echo "$ret" | /usr/bin/grep -oP "$version")"
    echo "$ret"
}

# zlib
zlib_ver="$(clean_html_index https://zlib.net/)"
zlib_ver="$(get_last_version "${zlib_ver}" zlib '1\.\d\.\d+')"
zlib_ver="${zlib_ver:-1.2.13}"
wget -c "https://zlib.net/zlib-${zlib_ver}.tar.gz"
tar xf "zlib-${zlib_ver}.tar.gz"
cd "zlib-${zlib_ver}" || exit 1
./configure \
    --static \
    --prefix=$PREFIX
make install -j $CPUCOUNT
cd ..
rm -rf "zlib-${zlib_ver}"

# openssl
openssl_ver="$(clean_html_index https://www.openssl.org/source/)"
openssl_ver="$(get_last_version "${openssl_ver}" openssl '3\.1\.\d+')"
openssl_ver="${openssl_ver:-3.1.2}"
wget -c "https://www.openssl.org/source/openssl-${openssl_ver}.tar.gz"
tar xf "openssl-${openssl_ver}.tar.gz"
cd "openssl-${openssl_ver}" || exit 1
./config \
    --prefix=$PREFIX \
    --libdir=lib \
    -static
make build_sw -j $CPUCOUNT
make install_sw
cd ..
rm -rf "openssl-${openssl_ver}"

# expat
expat_ver="$(clean_html_index https://sourceforge.net/projects/expat/files/expat/ 'expat/[0-9]+\.[0-9]+\.[0-9]+')"
expat_ver="$(get_last_version "${expat_ver}" expat '2\.\d+\.\d+')"
expat_ver="${expat_ver:-2.5.0}"
wget -c "https://downloads.sourceforge.net/project/expat/expat/${expat_ver}/expat-${expat_ver}.tar.gz"
tar xf "expat-${expat_ver}.tar.gz"
cd "expat-${expat_ver}" || exit 1
./configure \
    --disable-shared \
    --enable-static \
    --prefix=$PREFIX
make install -j $CPUCOUNT
cd ..
rm -rf "expat-${expat_ver}"

# sqlite
sqlite_ver=$(clean_html_index_sqlite "https://www.sqlite.org/download.html")
[[ ! "$sqlite_ver" ]] && sqlite_ver="2023/sqlite-autoconf-3420000.tar.gz"
sqlite_file=$(echo ${sqlite_ver} | grep -ioP "(sqlite-autoconf-\d+\.tar\.gz)")
wget -c "https://www.sqlite.org/${sqlite_ver}"
tar xf "${sqlite_file}"
echo ${sqlite_ver}
sqlite_name=$(echo ${sqlite_ver} | grep -ioP "(sqlite-autoconf-\d+)")
cd "${sqlite_name}" || exit 1
./configure \
    --disable-shared \
    --enable-static \
    --prefix=$PREFIX
make install -j $CPUCOUNT
cd ..
rm -rf "${sqlite_name}"

# c-ares
[[ ! "$cares_ver" ]] &&
    cares_ver="$(clean_html_index https://c-ares.org/)" &&
    cares_ver="$(get_last_version "$cares_ver" c-ares "1\.\d+\.\d")"
cares_ver="${cares_ver:-1.19.1}"
echo "c-ares-${cares_ver}"
wget -c "https://c-ares.org/download/c-ares-${cares_ver}.tar.gz"
tar xf "c-ares-${cares_ver}.tar.gz"
cd "c-ares-${cares_ver}" || exit 1
mkdir build
cd build
cmake \
    -G "Ninja" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCARES_STATIC=ON \
    -DCARES_SHARED=OFF \
    -DCMAKE_INSTALL_PREFIX=$PREFIX \
    ..
cmake --build . -j $CPUCOUNT
cmake --install .
cd ../..
rm -rf "c-ares-${cares_ver}"

# libssh2
[[ ! "$ssh_ver" ]] &&
    ssh_ver="$(clean_html_index https://libssh2.org/download/)" &&
    ssh_ver="$(get_last_version "$ssh_ver" tar.gz "1\.\d+\.\d")"
ssh_ver="${ssh_ver:-1.11.0}"
echo "${ssh_ver}"
wget -c "https://libssh2.org/download/libssh2-${ssh_ver}.tar.gz"
tar xf "libssh2-${ssh_ver}.tar.gz"
cd "libssh2-${ssh_ver}" || exit 1
patch -p1 -i ../libssh2-pkgconfig.patch
mkdir build
cd build
cmake \
    -G "Ninja" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_STATIC_LIBS=ON \
    -DBUILD_SHARED_LIBS=OFF \
    -DCRYPTO_BACKEND=OpenSSL \
    -DCMAKE_PREFIX_PATH=$PREFIX \
    -DCMAKE_INSTALL_PREFIX=$PREFIX \
    ..
cmake --build . -j $CPUCOUNT
cmake --install .
cd ../..
rm -rf "libssh2-${ssh_ver}"

# aria2
if [[ -d aria2 ]]; then
    cd aria2
    git checkout master || git checkout HEAD
    git reset --hard origin || git reset --hard
    git pull
else
    git clone https://github.com/aria2/aria2 --depth=1
    cd aria2 || exit 1
fi
git checkout -b patch
git am -3 ../aria2-*.patch

autoreconf -fi || autoreconf -fiv
./configure \
    --prefix=$PREFIX \
    --without-included-gettext \
    --disable-nls \
    --with-libcares \
    --without-gnutls \
    --without-wintls \
    --with-openssl \
    --with-sqlite3 \
    --without-libxml2 \
    --with-libexpat \
    --with-libz \
    --without-libgmp \
    --with-libssh2 \
    --without-libgcrypt \
    --without-libnettle \
    --with-cppunit-prefix=$PREFIX \
    --enable-shared=no \
    ARIA2_STATIC=yes \
    CPPFLAGS="-I$PREFIX/include" \
    LDFLAGS="-L$PREFIX/lib -Wl,--gc-sections,--build-id=none" \
    PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
make -j $CPUCOUNT
strip -s src/aria2c.exe
git checkout master
git branch patch -D
cd ..

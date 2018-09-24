#!/bin/sh

set -x

export BUILDDIR=`pwd`

if uname -s | grep -i 'linux' &> /dev/null; then
  IS_LINUX=1
fi

if [ $IS_LINUX ]; then
  NCPU=`cat /proc/cpuinfo | grep -c -i processor`
else
  NCPU=8
fi

NDK=`which ndk-build`
NDK=`dirname $NDK`
if [ $IS_LINUX ]; then
  NDK=`readlink -f $NDK`
fi

export CLANG=1

if [ -z "$ARCHS" ]; then
  ARCHS='arm64-v8a armeabi-v7a x86 x86_64'
fi

for ARCH in $ARCHS; do

cd $BUILDDIR

GCCPREFIX="`./setCrossEnvironment-$ARCH.sh sh -c 'basename $STRIP | sed s/-strip//'`"
echo "ARCH $ARCH GCCPREFIX $GCCPREFIX"

mkdir -p $ARCH
cd $BUILDDIR/$ARCH

# =========== libandroid_support.a ===========
ANDROID_SUPPORT=

if [ $ARCH = armeabi-v7a ] || [ $ARCH = x86 ]; then

ANDROID_SUPPORT=-landroid_support

[ -e libandroid_support.a ] || {
	mkdir -p android_support
	cd android_support
	ln -sf $NDK/sources/android/support jni

	#ndk-build -j$NCPU APP_ABI=$ARCH APP_MODULES=android_support LIBCXX_FORCE_REBUILD=true CLANG=1 || exit 1
	#cp -f obj/local/$ARCH/libandroid_support.a ../
	ln -sf $NDK/sources/cxx-stl/llvm-libc++/libs/$ARCH/libandroid_support.a ../

} || exit 1

fi

cd $BUILDDIR/$ARCH

# =========== libiconv.so ===========

[ -e libiconv.so ] || [ $SKIP_ICONV ] || {

	rm -rf libiconv-1.15

	tar xvf ../libiconv-1.15.tar.gz

	cd libiconv-1.15

	cp -f $BUILDDIR/config.sub build-aux/
	cp -f $BUILDDIR/config.guess build-aux/
	cp -f $BUILDDIR/config.sub libcharset/build-aux/
	cp -f $BUILDDIR/config.guess libcharset/build-aux/

	sed -i,tmp 's/MB_CUR_MAX/1/g' lib/loop_wchar.h

	env CFLAGS="-I$NDK/sources/android/support/include -D_IO_getc=getc" \
		LDFLAGS="-L$BUILDDIR/$ARCH $ANDROID_SUPPORT" \
		$BUILDDIR/setCrossEnvironment-$ARCH.sh \
		./configure \
		--host=$GCCPREFIX \
		--prefix=`pwd`/.. \
		--enable-static --enable-shared \
		|| exit 1

	env PATH=`pwd`:$PATH \
		$BUILDDIR/setCrossEnvironment-$ARCH.sh \
		make V=1 || echo "Libtool is a miserable pile of shit, linking libcharset.so manually"

	env PATH=`pwd`:$PATH \
		$BUILDDIR/setCrossEnvironment-$ARCH.sh \
		sh -c '$LD $CFLAGS $LDFLAGS -shared libcharset/lib/.libs/*.o -o libcharset/lib/.libs/libcharset.so' || exit 1

	env PATH=`pwd`:$PATH \
		$BUILDDIR/setCrossEnvironment-$ARCH.sh \
		make V=1 || echo "Libtool works worse than cat /dev/urandom | head 10000 > library.so, because this will at least generate a target file, linking libiconv.so manually"

	env PATH=`pwd`:$PATH \
		$BUILDDIR/setCrossEnvironment-$ARCH.sh \
		sh -c '$LD $CFLAGS $LDFLAGS -shared lib/.libs/*.o -o lib/.libs/libiconv.so' || exit 1

	env PATH=`pwd`:$PATH \
		$BUILDDIR/setCrossEnvironment-$ARCH.sh \
		make V=1 || echo "Did you know that libtool contributes to global warming by overheating your CPU?"

	cp -f lib/.libs/libiconv.so preload/preloadable_libiconv.so

	echo 'all install:' > src/Makefile
	echo '	touch $@' >> src/Makefile

	env PATH=`pwd`:$PATH \
		$BUILDDIR/setCrossEnvironment-$ARCH.sh \
		make V=1 || exit 1

	env PATH=`pwd`:$PATH \
		$BUILDDIR/setCrossEnvironment-$ARCH.sh \
		make V=1 install || exit 1

	cd ..

	for f in libiconv libcharset; do
		cp -f lib/$f.so ./
		$BUILDDIR/setCrossEnvironment-$ARCH.sh \
			sh -c '$STRIP'" $f.so"
	done

} || exit 1

# =========== libharfbuzz ===========

cd $BUILDDIR/$ARCH

[ -e libharfbuzz.a ] || [ $SKIP_HARFBUZZ ] || {
	rm -rf harfbuzz-1.4.6
	tar xvf ../harfbuzz-1.4.6.tar.bz2
	cd harfbuzz-1.4.6

	cp -f $BUILDDIR/config.sub .
	cp -f $BUILDDIR/config.guess .

	sed -i,tmp 's/ld_shlibs=no/ld_shlibs=yes/g' ./configure

	env CFLAGS="-I$NDK/sources/android/support/include -frtti -fexceptions -I$BUILDDIR/$ARCH/include" \
		LDFLAGS="-frtti -fexceptions -L$BUILDDIR/$ARCH/lib" \
		LIBS="-L$BUILDDIR/$ARCH $ANDROID_SUPPORT" \
		$BUILDDIR/setCrossEnvironment-$ARCH.sh \
		./configure \
		--host=$GCCPREFIX \
		--prefix=`pwd`/../ \
		--enable-static --enable-shared \
		--with-glib=no --with-gobject=no \
		--with-cairo=no --with-fontconfig=no \
		--with-icu=no --with-freetype=no \
		|| exit 1

	env PATH=`pwd`:$PATH \
		$BUILDDIR/setCrossEnvironment-$ARCH.sh \
		make -j$NCPU V=1 || echo "Crappy libtool cannot link anything"

	env PATH=`pwd`:$PATH \
		$BUILDDIR/setCrossEnvironment-$ARCH.sh \
		sh -c '$LD $CFLAGS $LDFLAGS -shared src/.libs/*.o src/hb-ucdn/.libs/*.o -o src/.libs/libharfbuzz.so' || exit 1

	env PATH=`pwd`:$PATH \
		$BUILDDIR/setCrossEnvironment-$ARCH.sh \
		make -j$NCPU V=1 || exit 1

	env PATH=`pwd`:$PATH \
		$BUILDDIR/setCrossEnvironment-$ARCH.sh \
		make V=1 install || exit 1

	env PATH=`pwd`:$PATH \
		$BUILDDIR/setCrossEnvironment-$ARCH.sh \
		sh -c '$AR rcs ../lib/libharfbuzz.a src/.libs/*.o src/hb-ucdn/.libs/*.o' || exit 1

	cd ..
	cp -f lib/libharfbuzz.a ./
}

# =========== libicuuc ===========

cd $BUILDDIR/$ARCH

[ -e libicuuc.a ] || [ -e libicuuc.so ] || [ $SKIP_ICUUC ] || {

	rm -rf icu

	tar xvf ../icu4c-59_1-src.tgz

	cd icu/source

	cp -f $BUILDDIR/config.sub .
	cp -f $BUILDDIR/config.guess .

	[ -d cross ] || {
		mkdir cross
		cd cross
		../configure || exit 1
		make -j$NCPU VERBOSE=1 || exit 1
		cd ..
	} || exit 1

	sed -i,tmp "s@LD_SONAME *=.*@LD_SONAME =@g" config/mh-linux
	sed -i,tmp "s%ln -s *%cp -f \$(dir \$@)/%g" config/mh-linux
	sed -i,tmp "s/#define U_OVERRIDE_CXX_ALLOCATION 1/#define U_OVERRIDE_CXX_ALLOCATION 0/g" common/unicode/uconfig.h

	if [ $SHARED_ICU ]; then
		libtype='--enable-shared --disable-static'
	else
		libtype='--enable-static --disable-shared'
	fi

	env CFLAGS="-I$NDK/sources/android/support/include -frtti -fexceptions" \
		LDFLAGS="-frtti -fexceptions -L$BUILDDIR/$ARCH/lib" \
		LIBS="-L$BUILDDIR/$ARCH $ANDROID_SUPPORT `$BUILDDIR/setCrossEnvironment-$ARCH.sh sh -c 'echo $LDFLAGS'`" \
		ac_cv_func_strtod_l=no \
		$BUILDDIR/setCrossEnvironment-$ARCH.sh \
		./configure \
		--host=$GCCPREFIX \
		--prefix=`pwd`/../../ \
		--with-cross-build=`pwd`/cross \
		$libtype \
		--with-data-packaging=archive \
		|| exit 1

#		ICULEHB_CFLAGS="-I$BUILDDIR/$ARCH/include" \
#		ICULEHB_LIBS="-licu-le-hb" \
#		--enable-layoutex \

	sed -i,tmp "s@^prefix *= *.*@prefix = .@" icudefs.mk || exit 1

	env PATH=`pwd`:$PATH \
		$BUILDDIR/setCrossEnvironment-$ARCH.sh \
		make -j$NCPU VERBOSE=1 || exit 1

	sed -i,tmp "s@^prefix *= *.*@prefix = `pwd`/../../@" icudefs.mk || exit 1

	env PATH=`pwd`:$PATH \
		$BUILDDIR/setCrossEnvironment-$ARCH.sh \
		make V=1 install || exit 1

	for f in libicudata libicutest libicui18n libicuio libicutu libicuuc; do
		if [ $SHARED_ICU ]; then
			cp -f -H ../../lib/$f.so ../../
		else
			cp -f ../../lib/$f.a ../../
		fi
		#$BUILDDIR/setCrossEnvironment-$ARCH.sh \
		#	sh -c '$STRIP'" ../../$f.so"
	done

} || exit 1

# =========== libicu-le-hb ===========

cd $BUILDDIR/$ARCH

[ -e libicu-le-hb.a ] || [ $SKIP_ICUUC ] || [ $SKIP_HARFBUZZ ] || [ $SKIP_ICULEHB ] || {
	rm -rf icu-le-hb-1.0.3
	tar xvf ../icu-le-hb-1.0.3.tar.gz
	cd icu-le-hb-1.0.3

	cp -f $BUILDDIR/config.sub .
	cp -f $BUILDDIR/config.guess .

	sed -i,tmp 's/ld_shlibs=no/ld_shlibs=yes/g' ./configure

	touch dummy.c
	env PATH=`pwd`:$PATH \
		$BUILDDIR/setCrossEnvironment-$ARCH.sh \
		sh -c '$CC $CFLAGS -c dummy.c -o src/crtbegin_so.o' || exit 1
	cp -f src/crtbegin_so.o src/crtend_so.o

	env CFLAGS="-I$NDK/sources/android/support/include -frtti -fexceptions" \
		CXXFLAGS="-std=c++11" \
		LDFLAGS="-frtti -fexceptions" \
		LIBS="-L$BUILDDIR/$ARCH $ANDROID_SUPPORT" \
		HARFBUZZ_CFLAGS="-I$BUILDDIR/$ARCH/include/harfbuzz" \
		HARFBUZZ_LIBS="-L$BUILDDIR/$ARCH/lib -lharfbuzz" \
		ICU_CFLAGS="-I$BUILDDIR/$ARCH/include" \
		ICU_LIBS="-L$BUILDDIR/$ARCH/lib" \
		$BUILDDIR/setCrossEnvironment-$ARCH.sh \
		./configure \
		--host=$GCCPREFIX \
		--prefix=`pwd`/../ \
		--enable-static --enable-shared \
		|| exit 1

	env PATH=`pwd`:$PATH \
		$BUILDDIR/setCrossEnvironment-$ARCH.sh \
		make V=1 || \
		env PATH=`pwd`:$PATH \
		$BUILDDIR/setCrossEnvironment-$ARCH.sh \
		sh -c '$LD $CFLAGS -shared src/.libs/*.o -o src/.libs/libicu-le-hb.so.0.0.0 -L../lib -lharfbuzz -licuuc $LDFLAGS' || exit 1

	env PATH=`pwd`:$PATH \
		$BUILDDIR/setCrossEnvironment-$ARCH.sh \
		sh -c '$AR rcs ../lib/libicu-le-hb.a src/.libs/*.o' || exit 1

	cat > src/libicu-le-hb.la <<EOF
# libicu-le-hb.so - a libtool library file
# Generated by libtool (GNU libtool) 2.4.2 Debian-2.4.2-1.7ubuntu1
#
# Please DO NOT delete this file!
# It is necessary for linking the library.

# The name that we can dlopen(3).
dlname='libicu-le-hb.so.0'

# Names of this library.
library_names='libicu-le-hb.so.0.0.0 libicu-le-hb.so.0 libicu-le-hb.so'

# The name of the static archive.
old_library=''

# Linker flags that can not go in dependency_libs.
inherited_linker_flags=''

# Libraries that this one depends upon.
dependency_libs=''

# Names of additional weak libraries provided by this library
weak_library_names=''

# Version information for libharfbuzz.
current=0
age=0
revision=0

# Is this an already installed library?
installed=no

# Should we warn about portability when linking against -modules?
shouldnotlink=no

# Files to dlopen/dlpreopen
dlopen=''
dlpreopen=''

# Directory that this library needs to be installed in:
libdir='/usr/lib'
EOF

	cp -f src/libicu-le-hb.la src/.libs/libicu-le-hb.lai

	env PATH=`pwd`:$PATH \
		$BUILDDIR/setCrossEnvironment-$ARCH.sh \
		make V=1 || exit 1

	env PATH=`pwd`:$PATH \
		$BUILDDIR/setCrossEnvironment-$ARCH.sh \
		make V=1 install || exit 1

	cd ..
	cp -f lib/libicu-le-hb.a ./
}

# =========== We are building libicu twice, because libiculx depends on libicu-le-hb wcich depends on libicudata ===========

cd $BUILDDIR/$ARCH

[ -e libiculx.a ] || [ $SKIP_HARFBUZZ ] || [ $SKIP_ICUUC ] || [ $SKIP_ICULEHB ] || [ $SKIP_ICULX ] || {

	cd icu/source

	env CFLAGS="-I$NDK/sources/android/support/include -frtti -fexceptions" \
		LDFLAGS="-frtti -fexceptions -L$BUILDDIR/$ARCH/lib" \
		LIBS="-L$BUILDDIR/$ARCH $ANDROID_SUPPORT `$BUILDDIR/setCrossEnvironment-$ARCH.sh sh -c 'echo $LDFLAGS'`" \
		ICULEHB_CFLAGS="-I$BUILDDIR/$ARCH/include/icu-le-hb" \
		ICULEHB_LIBS="-licu-le-hb" \
		$BUILDDIR/setCrossEnvironment-$ARCH.sh \
		./configure \
		--host=$GCCPREFIX \
		--prefix=`pwd`/../../ \
		--with-cross-build=`pwd`/cross \
		--enable-static --disable-shared \
		--with-data-packaging=archive \
		--enable-layoutex \
		|| exit 1

	sed -i,tmp "s@^prefix *= *.*@prefix = .@" icudefs.mk || exit 1

	env PATH=`pwd`:$PATH \
		$BUILDDIR/setCrossEnvironment-$ARCH.sh \
		make -j$NCPU VERBOSE=1 || exit 1

	sed -i,tmp "s@^prefix *= *.*@prefix = `pwd`/../../@" icudefs.mk || exit 1

	env PATH=`pwd`:$PATH \
		$BUILDDIR/setCrossEnvironment-$ARCH.sh \
		make V=1 install || exit 1

	for f in libicudata libicutest libicui18n libicuio libicutu libicuuc libiculx; do
		#cp -f -H ../../lib/$f.so ../../
		cp -f ../../lib/$f.a ../../ || exit 1
		#$BUILDDIR/setCrossEnvironment-$ARCH.sh \
		#	sh -c '$STRIP'" ../../$f.so"
	done

} || exit 1


done # for ARCH in ...

exit 0

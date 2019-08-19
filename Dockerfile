FROM alpine-llvm:latest AS build-ctx

ENV SRC=/srcroot \
    OUT=/buildroot \
    CC=/usr/bin/clang \
    CXX=/usr/bin/clang++ \
    CFLAGS="-O3 -DNDEBUG -pipe -flto"

WORKDIR $SRC
ADD *.tar.* ./

ENV HDF5_SRC=$SRC/hdf5-1.10.5 \
    NETCDF_C_SRC=$SRC/netcdf-c-4.7.0 \
    UDUNITS_SRC=$SRC/udunits-2.2.26 \
    NCO_SRC=$SRC/nco-4.8.1 \
    CXXFLAGS="$CFLAGS"

RUN apk add bash bison cunit-dev curl-dev expat-dev flex gsl-dev zlib-dev

# Dependency chain:
# hdf5 <- netcdf-c <- nco
#                   /
#         udunits <-

WORKDIR $HDF5_SRC
# @todo We should really be building and running the tests.
#       The CMake config doesn't expose a "no static libs" option
#       and the "testlibinfo" test fails with LTO since the static
#       "library" contains LLVM IR objects instead of object code.
RUN mkdir .build && \
    cd .build && \
    cmake .. -DBUILD_SHARED_LIBS=ON \
             -DBUILD_TESTING=OFF \
             -DCMAKE_BUILD_TYPE=Release \
             -DCMAKE_INSTALL_PREFIX=$OUT \
             -DHDF5_ENABLE_Z_LIB_SUPPORT=ON \
             -DHDF5_BUILD_EXAMPLES=OFF && \
    make -j$(nproc) && \
    make install

WORKDIR $NETCDF_C_SRC
RUN mkdir .build && \
    cd .build && \
    cmake .. -DCMAKE_BUILD_TYPE=Release \
             -DCMAKE_INSTALL_PREFIX=$OUT \
             -DCMAKE_INSTALL_LIBDIR=lib && \
    make -j$(nproc) && \
    make test && \
    make install

WORKDIR $UDUNITS_SRC
RUN mkdir .build && \
    cd .build && \
    cmake .. -DCMAKE_BUILD_TYPE=Release \
             -DCMAKE_INSTALL_PREFIX=$OUT && \
    make -j$(nproc) && \
    make test && \
    make install

WORKDIR $NCO_SRC
# The CMake build for NCO is horribly broken. Fall back to GNU.
RUN mkdir .build && \
    cd .build && \
    NETCDF_ROOT=$OUT NETCDF_LIB=$OUT/lib64 UDUNITS2_PATH=$OUT ../configure --prefix=$OUT --disable-static --disable-udunits && \
    make -j$(nproc) && \
    make install

# https://unix.stackexchange.com/questions/1484/how-to-find-all-binary-executables-recursively-within-a-directory
RUN find $OUT -type f -executable -exec sh -c 'test "$(head -c 2 "$1")" != "#!"' sh {} \; -print | \
    xargs -n1 -I{} strip {} || echo 'cant strip {}'

FROM alpine:latest

RUN apk upgrade && \
    apk add expat gsl libcurl libgcc libstdc++ nghttp2-libs

COPY --from=build-ctx /buildroot/ /usr/

             



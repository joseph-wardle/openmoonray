# Third-party dependencies for an OpenMoonRay build that runs inside
# SideFX Houdini 21 on EL9 (RHEL/Rocky/Alma 9).
#
# The rule that decides every entry in this file:
#
#   * If Houdini loads a library into its process under the SAME soname we
#     would produce (USD, Python, oneTBB, OIDN, OpenSubdiv, blosc, jpeg, png,
#     tiff, curl, freetype), we use Houdini's copy. Two different builds of
#     one soname cannot coexist in a process, so building our own would only
#     hide which one actually gets loaded.
#
#   * If Houdini only ships a renamed/namespaced copy (Boost→hboost,
#     OpenImageIO/OpenEXR/Imath/OCIO→*_sidefx, OpenVDB→*_sesi, embree3),
#     we build our own. They cannot collide, and we need CMake configs and
#     versions Houdini doesn't provide.
#
# The Houdini-provided pieces are exposed to CMake through the "hfs" shim
# installed to ${InstallRoot}/hfs (see ../hfs): a header directory that
# symlinks ONLY the headers we use, plus CMake package configs (pxr, TBB,
# OpenImageDenoise) that point at the real libraries in $HFS/dsolib.
# We never put $HFS/toolkit/include on the include path directly, because it
# also contains Houdini's OpenImageIO/OpenEXR/openvdb headers, which would
# silently shadow ours and then fail to link.
#
# Every download is pinned by SHA-256. Re-running with the same HFS,
# compiler and this file produces the same dependency set.

cmake_minimum_required(VERSION 3.23)
project(openmoonray_houdini21_deps NONE)

include(ExternalProject)
include(ProcessorCount)

set(HFS "" CACHE PATH "Houdini install root, e.g. /opt/hfs21.0.596")
set(InstallRoot "" CACHE PATH "Install prefix for the dependencies")
set(DownloadDir "${CMAKE_BINARY_DIR}/downloads" CACHE PATH
    "Where source archives are cached between builds")
set(ExpectedHoudiniVersion "21.0.596" CACHE STRING
    "Houdini build this dependency set is pinned to")

if(NOT HFS OR NOT EXISTS "${HFS}/toolkit/include/SYS/SYS_Version.h")
    message(FATAL_ERROR "Set -DHFS=<houdini install root> (no SYS_Version.h under '${HFS}')")
endif()
if(NOT InstallRoot)
    message(FATAL_ERROR "Set -DInstallRoot=<dependency install prefix>")
endif()

file(STRINGS "${HFS}/toolkit/include/SYS/SYS_Version.h" _hver
     REGEX "#define SYS_VERSION_FULL ")
string(REGEX REPLACE ".*\"(.*)\".*" "\\1" HoudiniVersion "${_hver}")
if(NOT HoudiniVersion STREQUAL ExpectedHoudiniVersion)
    # USD, Python and TBB are ABI-coupled to the exact Houdini build.
    message(FATAL_ERROR
        "HFS is Houdini ${HoudiniVersion}, but this dependency set is pinned to "
        "${ExpectedHoudiniVersion}. Pass -DExpectedHoudiniVersion=${HoudiniVersion} "
        "only after reviewing that its USD/TBB/Python versions are unchanged.")
endif()

ProcessorCount(NPROC)
set(HPYTHON_VERSION 3.11)
set(HPYTHON_EXE "${HFS}/python/bin/python${HPYTHON_VERSION}")
set(HPYTHON_INC "${HFS}/python/include/python${HPYTHON_VERSION}")
set(HFS_SHIM "${InstallRoot}/hfs")
set(HFS_INC "${HFS_SHIM}/include")
set(HFS_LIB "${HFS}/dsolib")

# Settings every CMake-based dependency shares.
set(common_cmake_args
    -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_INSTALL_PREFIX=${InstallRoot}
    -DCMAKE_INSTALL_LIBDIR=lib
    -DCMAKE_PREFIX_PATH=${InstallRoot}$<SEMICOLON>${HFS_SHIM}
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON
    -DCMAKE_CXX_STANDARD=17
    -DCMAKE_INSTALL_RPATH=${InstallRoot}/lib$<SEMICOLON>${HFS_LIB}
    -DCMAKE_POLICY_DEFAULT_CMP0074=NEW   # honour <Pkg>_ROOT hints
    -DBUILD_TESTING=OFF
)
set_property(DIRECTORY PROPERTY EP_BASE "${CMAKE_BINARY_DIR}/ep")
set(dl DOWNLOAD_DIR ${DownloadDir} DOWNLOAD_EXTRACT_TIMESTAMP ON)

# ---------------------------------------------------------------- toolchain

# CUDA from NVIDIA's per-component redistributables (hashes from
# redistrib_12.6.3.json) instead of the 4 GB runfile, which needs root.
# Houdini ships no libcudart, so the runtime lives in our prefix.
set(cuda_redist https://developer.download.nvidia.com/compute/cuda/redist)
set(cuda_components
    "cuda_nvcc/linux-x86_64/cuda_nvcc-linux-x86_64-12.6.85-archive.tar.xz|840deff234d9bef20d6856439c49881cb4f29423b214f9ecd2fa59b7ac323817"
    "cuda_cudart/linux-x86_64/cuda_cudart-linux-x86_64-12.6.77-archive.tar.xz|f74689258a60fd9c5bdfa7679458527a55e22442691ba678dcfaeffbf4391ef9"
    "cuda_cccl/linux-x86_64/cuda_cccl-linux-x86_64-12.6.77-archive.tar.xz|9c3145ef01f73e50c0f5fcf923f0899c847f487c529817daa8f8b1a3ecf20925"
)
set(cuda_targets)
foreach(entry ${cuda_components})
    string(REPLACE "|" ";" entry "${entry}")
    list(GET entry 0 path)
    list(GET entry 1 sha)
    get_filename_component(name "${path}" NAME_WE)
    string(REGEX REPLACE "-linux-x86_64.*" "" name "${name}")
    ExternalProject_Add(${name}
        URL ${cuda_redist}/${path} URL_HASH SHA256=${sha} ${dl}
        CONFIGURE_COMMAND "" BUILD_COMMAND ""
        INSTALL_COMMAND ${CMAKE_COMMAND} -E copy_directory <SOURCE_DIR> ${InstallRoot}/cuda
    )
    list(APPEND cuda_targets ${name})
endforeach()
# The redist archives use lib/, but nvcc.profile and FindCUDAToolkit expect
# the full toolkit's lib64/.
add_custom_target(CUDA ALL
    COMMAND ${CMAKE_COMMAND} -E create_symlink lib ${InstallRoot}/cuda/lib64
    DEPENDS ${cuda_targets})

# For third-party builds that can't set their own install RUNPATH (Boost's
# b2, Embree's packaging overrides CMAKE_INSTALL_RPATH); see set_runpath.cmake.
ExternalProject_Add(Patchelf
    URL https://github.com/NixOS/patchelf/releases/download/0.18.0/patchelf-0.18.0.tar.gz
    URL_HASH SHA256=64de10e4c6b8b8379db7e87f58030f336ea747c0515f381132e810dbf84a86e7 ${dl}
    CONFIGURE_COMMAND <SOURCE_DIR>/configure --prefix=<INSTALL_DIR>
    BUILD_COMMAND $(MAKE)
    INSTALL_COMMAND $(MAKE) install
)
ExternalProject_Get_Property(Patchelf INSTALL_DIR)
set(PATCHELF ${INSTALL_DIR}/bin/patchelf)

# set_runpath(<project> <glob> [extra dirs...]): after <project> installs,
# set RUNPATH to $ORIGIN plus the extra dirs on every library matching <glob>.
function(set_runpath project glob)
    ExternalProject_Add_Step(${project} set_runpath
        COMMAND ${CMAKE_COMMAND} -DPATCHELF=${PATCHELF} "-DGLOB=${glob}"
                "-DEXTRA_DIRS=${ARGN}" -P ${CMAKE_CURRENT_SOURCE_DIR}/set_runpath.cmake
        DEPENDEES install
        DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/set_runpath.cmake
    )
    ExternalProject_Add_StepDependencies(${project} set_runpath Patchelf)
endfunction()

ExternalProject_Add(ISPC
    URL https://github.com/ispc/ispc/releases/download/v1.21.0/ispc-v1.21.0-linux.tar.gz
    URL_HASH SHA256=fe658893799af46c9cac0153f0bdc9a2ff93541fff9b17cf6b09ffc7576cfdcc ${dl}
    CONFIGURE_COMMAND "" BUILD_COMMAND ""
    INSTALL_COMMAND ${CMAKE_COMMAND} -E copy <SOURCE_DIR>/bin/ispc ${InstallRoot}/bin/ispc
)

# ---------------------------------------------------------- Houdini shim

# Configures ../hfs into ${HFS_SHIM}. Runs at build time so a changed HFS is
# picked up by a re-build without wiping the cache.
ExternalProject_Add(HoudiniShim
    SOURCE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../hfs
    CMAKE_ARGS
        -DHFS=${HFS}
        -DCMAKE_INSTALL_PREFIX=${HFS_SHIM}
    BUILD_ALWAYS ON
)

# Headers for Houdini's libcurl.so.4 (8.9.1) and libfreetype.so.6 (2.9.1),
# which ship without them. Version-matched to the binaries.
ExternalProject_Add(CurlHeaders
    URL https://curl.se/download/curl-8.9.1.tar.xz
    URL_HASH SHA256=f292f6cc051d5bbabf725ef85d432dfeacc8711dd717ea97612ae590643801e5 ${dl}
    CONFIGURE_COMMAND "" BUILD_COMMAND ""
    INSTALL_COMMAND ${CMAKE_COMMAND} -E copy_directory <SOURCE_DIR>/include/curl ${HFS_INC}/curl
    DEPENDS HoudiniShim
)
ExternalProject_Add(FreeTypeHeaders
    URL https://downloads.sourceforge.net/project/freetype/freetype2/2.9.1/freetype-2.9.1.tar.gz
    URL_HASH SHA256=ec391504e55498adceb30baceebd147a6e963f636eb617424bcfc47a169898ce ${dl}
    CONFIGURE_COMMAND "" BUILD_COMMAND ""
    INSTALL_COMMAND ${CMAKE_COMMAND} -E copy_directory <SOURCE_DIR>/include ${HFS_INC}/freetype2
    DEPENDS HoudiniShim
)

# ------------------------------------------------------------------- boost

# Real Boost (Houdini's is renamed to hboost). Boost.Python is built against
# Houdini's Python 3.11 so py_scene_rdl2 imports in hython.
file(WRITE ${CMAKE_BINARY_DIR}/boost-user-config.jam
    "using python : ${HPYTHON_VERSION} : ${HPYTHON_EXE} : ${HPYTHON_INC} : ${HFS}/python/lib ;\n")
ExternalProject_Add(Boost
    URL https://archives.boost.io/release/1.85.0/source/boost_1_85_0.tar.gz
    URL_HASH SHA256=be0d91732d5b0cc6fbb275c7939974457e79b54d6f07ce2e3dfdd68bef883b0b ${dl}
    BUILD_IN_SOURCE ON
    CONFIGURE_COMMAND ./bootstrap.sh --prefix=${InstallRoot}
    BUILD_COMMAND ./b2 -j${NPROC} -d0
        --user-config=${CMAKE_BINARY_DIR}/boost-user-config.jam
        --prefix=${InstallRoot} --layout=system
        variant=release link=shared threading=multi runtime-link=shared
        cxxflags=-fPIC cxxstd=17 python=${HPYTHON_VERSION}
        --with-atomic --with-chrono --with-date_time --with-filesystem
        --with-iostreams --with-program_options --with-python --with-regex
        --with-system --with-thread
        # iostreams is only for OpenVDB's mmap'd delayed loading; no codecs.
        -sNO_BZIP2=1 -sNO_ZLIB=1 -sNO_LZMA=1 -sNO_ZSTD=1
        install
    INSTALL_COMMAND ""
)
# e.g. boost_filesystem needs boost_atomic from the same directory.
set_runpath(Boost "${InstallRoot}/lib/libboost_*.so.*")

# ----------------------------------------------------- small C/C++ libraries

ExternalProject_Add(JsonCpp
    URL https://github.com/open-source-parsers/jsoncpp/archive/refs/tags/1.9.5.tar.gz
    URL_HASH SHA256=f409856e5920c18d0c2fb85276e24ee607d2a09b5e7d5f0a371368903c275da2 ${dl}
    CMAKE_ARGS ${common_cmake_args}
        -DBUILD_SHARED_LIBS=ON -DBUILD_STATIC_LIBS=OFF -DBUILD_OBJECT_LIBS=OFF
        -DJSONCPP_WITH_TESTS=OFF -DJSONCPP_WITH_POST_BUILD_UNITTEST=OFF
        -DJSONCPP_WITH_PKGCONFIG_SUPPORT=OFF
)

ExternalProject_Add(Log4cplus
    URL https://github.com/log4cplus/log4cplus/releases/download/REL_2_0_5/log4cplus-2.0.5.tar.gz
    URL_HASH SHA256=c07115c23219390633798def30b7b51a0f79fdeb857e4b49632f17746d0ceb97 ${dl}
    CMAKE_ARGS ${common_cmake_args}
        -DBUILD_SHARED_LIBS=ON -DUNICODE=OFF
        -DLOG4CPLUS_BUILD_TESTING=OFF -DLOG4CPLUS_BUILD_LOGGINGSERVER=OFF
        -DWITH_UNIT_TESTS=OFF
)

# Lua is linked statically into libscene_rdl2, hence -fPIC.
ExternalProject_Add(Lua
    URL https://www.lua.org/ftp/lua-5.4.4.tar.gz
    URL_HASH SHA256=164c7849653b80ae67bec4b7473b884bf5cc8d2dca05653475ec2ed27b9ebf61 ${dl}
    BUILD_IN_SOURCE ON
    CONFIGURE_COMMAND ""
    BUILD_COMMAND $(MAKE) linux MYCFLAGS=-fPIC
    INSTALL_COMMAND $(MAKE) install INSTALL_TOP=${InstallRoot}
)

ExternalProject_Add(CppUnit
    URL https://dev-www.libreoffice.org/src/cppunit-1.15.1.tar.gz
    URL_HASH SHA256=89c5c6665337f56fd2db36bc3805a5619709d51fb136e51937072f63fcc717a7 ${dl}
    CONFIGURE_COMMAND <SOURCE_DIR>/configure --prefix=${InstallRoot}
        --disable-static --disable-doxygen --disable-werror
    BUILD_COMMAND $(MAKE)
    INSTALL_COMMAND $(MAKE) install
)

ExternalProject_Add(MicroHttpd
    URL https://ftp.gnu.org/gnu/libmicrohttpd/libmicrohttpd-0.9.72.tar.gz
    URL_HASH SHA256=0ae825f8e0d7f41201fd44a0df1cf454c1cb0bc50fe9d59c26552260264c2ff8 ${dl}
    CONFIGURE_COMMAND <SOURCE_DIR>/configure --prefix=${InstallRoot}
        --disable-static --disable-https --without-gnutls
        --disable-doc --disable-examples
    BUILD_COMMAND $(MAKE)
    INSTALL_COMMAND $(MAKE) install
)

# Headers only: the OS's util-linux libuuid.so.1 is used at runtime. A
# separately built libuuid (e.g. the 1.0.3 fork upstream's macOS recipe uses)
# has the same soname but no symbol versions, which breaks X11's libSM.
# Version-matched to EL9's libuuid-2.37.4.
ExternalProject_Add(UuidHeaders
    URL https://mirrors.edge.kernel.org/pub/linux/utils/util-linux/v2.37/util-linux-2.37.4.tar.xz
    URL_HASH SHA256=634e6916ad913366c3536b6468e7844769549b99a7b2bf80314de78ab5655b83 ${dl}
    CONFIGURE_COMMAND "" BUILD_COMMAND ""
    INSTALL_COMMAND ${CMAKE_COMMAND} -E copy <SOURCE_DIR>/libuuid/src/uuid.h ${InstallRoot}/include/uuid/uuid.h
)

ExternalProject_Add(Random123
    URL https://github.com/DEShawResearch/random123/archive/refs/tags/v1.14.0.tar.gz
    URL_HASH SHA256=effafd8656b18030b2a5b995cd3650c51a7c45052e6e1c21e48b9fa7a59d926e ${dl}
    CONFIGURE_COMMAND "" BUILD_COMMAND ""
    INSTALL_COMMAND ${CMAKE_COMMAND} -E copy_directory <SOURCE_DIR>/include ${InstallRoot}/include
)

# MoonRay calls optixModuleCreateFromPTX (removed in 7.7) and
# OPTIX_DENOISER_ALPHA_MODE_COPY (added in 7.5), so it needs exactly 7.5-7.6.
# Header-only; the implementation comes from the NVIDIA driver.
ExternalProject_Add(OptiX
    URL https://github.com/NVIDIA/optix-dev/archive/refs/tags/v7.6.0.tar.gz
    URL_HASH SHA256=4fe1e047d0e80980e57c469e3491f88cd3c3b735462b35cb3a0c2797a751fb1e ${dl}
    CONFIGURE_COMMAND "" BUILD_COMMAND ""
    INSTALL_COMMAND ${CMAKE_COMMAND} -E copy_directory <SOURCE_DIR>/include ${InstallRoot}/optix/include
)

# ----------------------------------------------------------- image stack

ExternalProject_Add(Imath
    URL https://github.com/AcademySoftwareFoundation/Imath/archive/refs/tags/v3.1.12.tar.gz
    URL_HASH SHA256=8a1bc258f3149b5729c2f4f8ffd337c0e57f09096e4ba9784329f40c4a9035da ${dl}
    CMAKE_ARGS ${common_cmake_args} -DPYTHON=OFF -DIMATH_INSTALL_PKG_CONFIG=OFF
)

# OpenEXR 3.3 otherwise FetchContent's libdeflate at configure time.
ExternalProject_Add(Libdeflate
    URL https://github.com/ebiggers/libdeflate/archive/refs/tags/v1.19.tar.gz
    URL_HASH SHA256=27bf62d71cd64728ff43a9feb92f2ac2f2bf748986d856133cc1e51992428c25 ${dl}
    CMAKE_ARGS ${common_cmake_args}
        -DLIBDEFLATE_BUILD_STATIC_LIB=OFF -DLIBDEFLATE_BUILD_GZIP=OFF
)

ExternalProject_Add(OpenEXR
    URL https://github.com/AcademySoftwareFoundation/openexr/archive/refs/tags/v3.3.2.tar.gz
    URL_HASH SHA256=5013e964de7399bff1dd328cbf65d239a989a7be53255092fa10b85a8715744d ${dl}
    CMAKE_ARGS ${common_cmake_args}
        -DOPENEXR_BUILD_TOOLS=OFF -DOPENEXR_BUILD_EXAMPLES=OFF
        -DOPENEXR_INSTALL_EXAMPLES=OFF -DOPENEXR_INSTALL_PKG_CONFIG=OFF
        -DOPENEXR_FORCE_INTERNAL_IMATH=OFF -DOPENEXR_FORCE_INTERNAL_DEFLATE=OFF
    DEPENDS Imath Libdeflate
)

# OCIO vendors yaml-cpp/expat/pystring/minizip-ng; with MISSING it fetches
# the exact versions pinned in its own source tree and links them statically.
ExternalProject_Add(OpenColorIO
    URL https://github.com/AcademySoftwareFoundation/OpenColorIO/archive/refs/tags/v2.4.1.tar.gz
    URL_HASH SHA256=d4eb15408b33dffd6ba0bba9a53328085b40bdd9319fa3d0d7348d06a8cbe842 ${dl}
    CMAKE_ARGS ${common_cmake_args}
        -DOCIO_BUILD_APPS=OFF -DOCIO_BUILD_TESTS=OFF -DOCIO_BUILD_GPU_TESTS=OFF
        -DOCIO_BUILD_PYTHON=OFF -DOCIO_BUILD_DOCS=OFF -DOCIO_BUILD_OPENFX=OFF
        -DOCIO_INSTALL_EXT_PACKAGES=MISSING
    DEPENDS Imath
)

ExternalProject_Add(Fmt
    URL https://github.com/fmtlib/fmt/archive/refs/tags/10.2.1.tar.gz
    URL_HASH SHA256=1250e4cc58bf06ee631567523f48848dc4596133e163f02615c97f78bab6c811 ${dl}
    CMAKE_ARGS ${common_cmake_args} -DFMT_DOC=OFF -DFMT_TEST=OFF
)

ExternalProject_Add(RobinMap
    URL https://github.com/Tessil/robin-map/archive/refs/tags/v1.3.0.tar.gz
    URL_HASH SHA256=a8424ad3b0affd4c57ed26f0f3d8a29604f0e1f2ef2089f497f614b1c94c7236 ${dl}
    CMAKE_ARGS ${common_cmake_args}
)

# Tools (oiiotool, maketx, idiff) are kept: maketx converts textures to the
# tiled/mipmapped form MoonRay expects, and the RATS tests need idiff/oiiotool.
# jpeg/png/tiff/zlib come from Houdini via the shim (same sonames).
ExternalProject_Add(OpenImageIO
    URL https://github.com/AcademySoftwareFoundation/OpenImageIO/archive/refs/tags/v2.5.18.0.tar.gz
    URL_HASH SHA256=f57481435cec18633d3eba9b2e8c483fc1df6f0a01c5c9f98cbae6d1c52928e5 ${dl}
    CMAKE_ARGS ${common_cmake_args}
        -DOIIO_BUILD_TESTS=OFF -DOIIO_BUILD_DOCS=OFF -DINSTALL_DOCS=OFF
        -DOIIO_BUILD_TOOLS=ON -DUSE_PYTHON=OFF -DUSE_QT=OFF -DBUILD_MISSING_DEPS=OFF
        -DUSE_FFMPEG=OFF -DUSE_OPENCV=OFF -DUSE_DCMTK=OFF -DUSE_LIBRAW=OFF
        -DUSE_WEBP=OFF -DUSE_LIBHEIF=OFF -DUSE_GIF=OFF -DUSE_OPENJPEG=OFF
        -DUSE_PTEX=OFF -DUSE_OPENVDB=OFF -DUSE_FIELD3D=OFF -DUSE_NUKE=OFF
        -DUSE_JXL=OFF -DUSE_R3DSDK=OFF -DUSE_LIBSQUISH=OFF
        -DEMBEDPLUGINS=ON -DSTOP_ON_WARNING=OFF -DOIIO_INTERNALIZE_FMT=ON
        -DJPEG_INCLUDE_DIR=${HFS_INC} -DJPEG_LIBRARY=${HFS_LIB}/libjpeg.so.8
        -DPNG_PNG_INCLUDE_DIR=${HFS_INC} -DPNG_LIBRARY=${HFS_LIB}/libpng16.so.16
        -DTIFF_INCLUDE_DIR=${HFS_INC} -DTIFF_LIBRARY=${HFS_LIB}/libtiff.so.6
        -DUSE_TBB=ON -DTBB_DIR=${HFS_SHIM}/lib/cmake/TBB
        -DBoost_ROOT=${InstallRoot} -DBoost_NO_SYSTEM_PATHS=ON
    DEPENDS Boost OpenEXR OpenColorIO Fmt RobinMap HoudiniShim
)

# ------------------------------------------------------ rendering libraries

# Built against Houdini's oneTBB; our soname/namespace (openvdb::v12_0)
# differs from Houdini's libopenvdb_sesi, so both can load.
ExternalProject_Add(OpenVDB
    URL https://github.com/AcademySoftwareFoundation/openvdb/archive/refs/tags/v12.0.1.tar.gz
    URL_HASH SHA256=a3c8724ecadabaf558b6e1bd6f1d695e93b82a7cfdf144b8551e5253340ddce0 ${dl}
    CMAKE_ARGS ${common_cmake_args}
        -DOPENVDB_BUILD_BINARIES=OFF -DOPENVDB_BUILD_PYTHON_MODULE=OFF
        -DOPENVDB_BUILD_UNITTESTS=OFF -DOPENVDB_BUILD_DOCS=OFF
        -DOPENVDB_CORE_STATIC=OFF -DUSE_BLOSC=ON -DUSE_ZLIB=ON
        -DUSE_LOG4CPLUS=ON -DUSE_IMATH_HALF=OFF -DUSE_EXR=OFF -DUSE_PKGCONFIG=OFF
        -DUSE_EXPLICIT_INSTANTIATION=ON
        -DTBB_INCLUDEDIR=${HFS_INC} -DTBB_LIBRARYDIR=${HFS_LIB}
        -DBlosc_INCLUDE_DIR=${HFS_INC} -DBlosc_LIBRARY=${HFS_LIB}/libblosc.so.1
        -DLog4cplus_ROOT=${InstallRoot}
        -DBoost_ROOT=${InstallRoot} -DBoost_NO_SYSTEM_PATHS=ON
    DEPENDS Boost Log4cplus HoudiniShim
)

# Embree 4 (MoonRay needs >= 4.2; Houdini only has embree3). Runtime ISA
# dispatch up to AVX-512, so one build serves every lab CPU.
ExternalProject_Add(Embree
    URL https://github.com/embree/embree/archive/refs/tags/v4.2.0.tar.gz
    URL_HASH SHA256=b0479ce688045d17aa63ce6223c84b1cdb5edbf00d7eda71c06b7e64e21f53a0 ${dl}
    CMAKE_ARGS ${common_cmake_args}
        -DEMBREE_ISPC_SUPPORT=ON -DEMBREE_ISPC_EXECUTABLE=${InstallRoot}/bin/ispc
        -DEMBREE_IGNORE_INVALID_RAYS=ON -DEMBREE_RAY_MASK=ON
        -DEMBREE_MAX_ISA=AVX512 -DEMBREE_TUTORIALS=OFF -DEMBREE_TESTING_INSTALL_TESTS=OFF
        -DEMBREE_TASKING_SYSTEM=TBB -DEMBREE_TBB_ROOT=${HFS_SHIM}
        -DTBB_DIR=${HFS_SHIM}/lib/cmake/TBB
    DEPENDS ISPC HoudiniShim
)
set_runpath(Embree "${InstallRoot}/lib/libembree4.so.*" ${HFS_LIB})

# Initial cache for configuring OpenMoonRay against Houdini 21. Used as
#
#   cmake -S <openmoonray> -B <build> -C building/houdini21/moonray.cmake \
#         -DHFS=/opt/hfs21.0.596 -DOMR_DEPS=<deps prefix> -DCMAKE_INSTALL_PREFIX=<prefix>
#
# build.sh does this for you. Every input MoonRay looks for is set here
# explicitly, so the result does not depend on environment variables or on
# whatever happens to be installed on the build machine. The rule for which
# libraries come from Houdini is explained in deps/CMakeLists.txt.

if(NOT HFS OR NOT OMR_DEPS)
    message(FATAL_ERROR "moonray.cmake needs -DHFS=<houdini root> and -DOMR_DEPS=<deps prefix>")
endif()

set(_shim "${OMR_DEPS}/hfs")
set(_shim_inc "${_shim}/include")
set(_dsolib "${HFS}/dsolib")

set(CMAKE_BUILD_TYPE Release CACHE STRING "")
set(CMAKE_PREFIX_PATH "${OMR_DEPS};${_shim}" CACHE STRING "")
# Never fall back to /usr for a library we provide (e.g. a stray system Boost).
set(Boost_NO_SYSTEM_PATHS ON CACHE BOOL "")
set(Boost_ROOT "${OMR_DEPS}" CACHE PATH "")

# ------------------------------------------------------------ Houdini-provided
set(pxr_DIR "${_shim}/lib/cmake/pxr" CACHE PATH "")
set(TBB_DIR "${_shim}/lib/cmake/TBB" CACHE PATH "")
set(OpenImageDenoise_DIR "${_shim}/lib/cmake/OpenImageDenoise" CACHE PATH "")

set(Python_EXECUTABLE "${HFS}/python/bin/python3.11" CACHE FILEPATH "")
set(Python_INCLUDE_DIR "${HFS}/python/include/python3.11" CACHE PATH "")
set(Python_LIBRARY "${HFS}/python/lib/libpython3.11.so.1.0" CACHE FILEPATH "")
set(BOOST_PYTHON_COMPONENT_NAME python311 CACHE STRING "")

set(OpenSubDiv_INCLUDE_DIR "${_shim_inc}" CACHE PATH "")
set(OpenSubDiv_CPU_LIBRARY "${_dsolib}/libosdCPU.so.3.6.0" CACHE FILEPATH "")
set(OpenSubDiv_GPU_LIBRARY "${_dsolib}/libosdGPU.so.3.6.0" CACHE FILEPATH "")

set(JPEG_INCLUDE_DIR "${_shim_inc}" CACHE PATH "")
set(JPEG_LIBRARY "${_dsolib}/libjpeg.so.8" CACHE FILEPATH "")

# FindLibcurl wants the directory holding curl.h, then adds /.. itself.
set(Libcurl_INCLUDE_DIR "${_shim_inc}/curl" CACHE PATH "")
set(Libcurl_LIBRARY "${_dsolib}/libcurl.so.4" CACHE FILEPATH "")

set(FreeType_INCLUDE_DIR "${_shim_inc}/freetype2" CACHE PATH "")
set(FreeType_LIBRARIES "${_dsolib}/libfreetype.so.6" CACHE FILEPATH "")

# ---------------------------------------------------------------- OS libuuid
# util-linux libuuid; headers come from deps (no libuuid-devel on the labs).
# The code includes <uuid/uuid.h>, and deps installs include/uuid/uuid.h.
set(Libuuid_INCLUDE_DIRS "${OMR_DEPS}/include" CACHE PATH "")
set(Libuuid_LIBRARY "/usr/lib64/libuuid.so.1" CACHE FILEPATH "")

# ------------------------------------------------------------- our toolchain
set(CMAKE_ISPC_COMPILER "${OMR_DEPS}/bin/ispc" CACHE FILEPATH "")
set(CUDAToolkit_ROOT "${OMR_DEPS}/cuda" CACHE PATH "")
set(CMAKE_CUDA_COMPILER "${OMR_DEPS}/cuda/bin/nvcc" CACHE FILEPATH "")
set(OptiX_INCLUDE_DIRS "${OMR_DEPS}/optix/include" CACHE PATH "")
set(IDIFF "${OMR_DEPS}/bin/idiff" CACHE FILEPATH "")
set(OIIOTOOL "${OMR_DEPS}/bin/oiiotool" CACHE FILEPATH "")

# ------------------------------------------------------------------ features
set(MOONRAY_USE_OPTIX ON CACHE BOOL "XPU mode and GPU denoising")
set(BUILD_MATERIALX_SHADERS ON CACHE BOOL "MaterialX pattern nodes as MoonRay maps")
set(MOONRAY_DENOISER_TARGET_ARCHITECTURE AVX2 CACHE STRING "")
# moonray_gui and arras_render need Qt5 (+QtScript); Houdini ships Qt6 only.
# They are standalone viewers, never loaded into Houdini.
set(BUILD_QT_APPS OFF CACHE BOOL "")
# Keep the default C++ ABI so we match Houdini (-fabi-version would not).
set(ABI_SET_VERSION OFF CACHE BOOL "")
# Unit tests are not installed; RATS image tests are run separately.
set(BUILD_TESTING OFF CACHE BOOL "")

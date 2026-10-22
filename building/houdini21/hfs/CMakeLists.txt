# Exposes the libraries MoonRay must share with Houdini (see the rule in
# ../deps/CMakeLists.txt) as ordinary CMake packages:
#
#   <prefix>/include/                  symlinks to the few Houdini headers we use
#   <prefix>/lib/cmake/pxr/            pxrConfig.cmake  (USD, generated from $HFS)
#   <prefix>/lib/cmake/TBB/            TBBConfig.cmake  (oneTBB)
#   <prefix>/lib/cmake/OpenImageDenoise/
#
# Libraries are referenced at their real location in $HFS/dsolib, never via
# symlinks: Houdini's libs find their own dependencies through $ORIGIN, which
# only works when they are loaded from dsolib itself.
#
# Upstream's building/Rocky9/pxr-houdini hand-lists USD targets for one
# Houdini/USD/Python version. Here everything is derived from $HFS at
# configure time, so the only Houdini-specific input is the HFS path.

cmake_minimum_required(VERSION 3.23)
project(hfs_shim NONE)

set(HFS "" CACHE PATH "Houdini install root")
if(NOT EXISTS "${HFS}/toolkit/include/pxr/pxr.h")
    message(FATAL_ERROR "No USD headers under HFS='${HFS}'")
endif()

set(HFS_TOOLKIT_INC "${HFS}/toolkit/include")
set(HFS_DSOLIB "${HFS}/dsolib")
set(HFS_PYTHON_VERSION 3.11)
set(HFS_PYTHON_INC "${HFS}/python/include/python${HFS_PYTHON_VERSION}")
set(HFS_PYTHON_LIB "${HFS}/python/lib/libpython${HFS_PYTHON_VERSION}.so.1.0")
set(SHIM_INC "${CMAKE_INSTALL_PREFIX}/include")

# --------------------------------------------------------------- headers

# Deliberately NOT the whole toolkit/include: it also holds Houdini's
# OpenImageIO/OpenEXR/Imath/openvdb headers, which must not shadow ours.
set(shared_headers
    pxr tbb oneapi OpenImageDenoise opensubdiv
    jpeglib.h jconfig.h jerror.h jmorecfg.h
    png.h pngconf.h pnglibconf.h
    tiff.h tiffconf.h tiffio.h tiffvers.h
    blosc.h blosc-export.h
)
foreach(h ${shared_headers})
    if(EXISTS "${HFS_TOOLKIT_INC}/${h}")
        install(CODE "
            file(MAKE_DIRECTORY \"${SHIM_INC}\")
            file(REMOVE \"${SHIM_INC}/${h}\")
            file(CREATE_LINK \"${HFS_TOOLKIT_INC}/${h}\" \"${SHIM_INC}/${h}\" SYMBOLIC)
        ")
    endif()
endforeach()

# ------------------------------------------------------------------ oneTBB

file(STRINGS "${HFS_TOOLKIT_INC}/oneapi/tbb/version.h" _v REGEX "#define TBB_VERSION_(MAJOR|MINOR|PATCH) ")
string(REGEX REPLACE ".*MAJOR ([0-9]+).*" "\\1" TBB_MAJOR "${_v}")
string(REGEX REPLACE ".*MINOR ([0-9]+).*" "\\1" TBB_MINOR "${_v}")
set(TBB_VERSION "${TBB_MAJOR}.${TBB_MINOR}")
configure_file(TBBConfig.cmake.in TBBConfig.cmake @ONLY)
configure_file(TBBConfigVersion.cmake.in TBBConfigVersion.cmake @ONLY)
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/TBBConfig.cmake
              ${CMAKE_CURRENT_BINARY_DIR}/TBBConfigVersion.cmake
        DESTINATION lib/cmake/TBB)

# -------------------------------------------------------- OpenImageDenoise

file(STRINGS "${HFS_TOOLKIT_INC}/OpenImageDenoise/config.h" _v REGEX "#define OIDN_VERSION_STRING ")
string(REGEX REPLACE ".*\"(.*)\".*" "\\1" OIDN_VERSION "${_v}")
configure_file(OpenImageDenoiseConfig.cmake.in OpenImageDenoiseConfig.cmake @ONLY)
configure_file(OpenImageDenoiseConfigVersion.cmake.in OpenImageDenoiseConfigVersion.cmake @ONLY)
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/OpenImageDenoiseConfig.cmake
              ${CMAKE_CURRENT_BINARY_DIR}/OpenImageDenoiseConfigVersion.cmake
        DESTINATION lib/cmake/OpenImageDenoise)

# --------------------------------------------------------------------- USD

file(STRINGS "${HFS_TOOLKIT_INC}/pxr/pxr.h" _v REGEX "#define PXR_(MAJOR|MINOR|PATCH)_VERSION ")
string(REGEX REPLACE ".*MAJOR_VERSION ([0-9]+).*" "\\1" PXR_MAJOR_VERSION "${_v}")
string(REGEX REPLACE ".*MINOR_VERSION ([0-9]+).*" "\\1" PXR_MINOR_VERSION "${_v}")
string(REGEX REPLACE ".*PATCH_VERSION ([0-9]+).*" "\\1" PXR_PATCH_VERSION "${_v}")
math(EXPR PXR_VERSION "${PXR_MAJOR_VERSION} * 10000 + ${PXR_MINOR_VERSION} * 100 + ${PXR_PATCH_VERSION}")

# One imported target per libpxr_<name>.so, named <name> like a stock USD
# install, linked to the other pxr libs it actually depends on (read from
# each library's DT_NEEDED entries).
find_program(READELF readelf REQUIRED)
file(GLOB pxr_libs RELATIVE "${HFS_DSOLIB}" "${HFS_DSOLIB}/libpxr_*.so")
list(SORT pxr_libs)
set(PXR_TARGET_DEFS "")
set(PXR_TARGET_NAMES "")
foreach(lib ${pxr_libs})
    string(REGEX REPLACE "^libpxr_(.*)\\.so$" "\\1" name "${lib}")
    execute_process(COMMAND ${READELF} -d "${HFS_DSOLIB}/${lib}"
                    OUTPUT_VARIABLE dyn COMMAND_ERROR_IS_FATAL ANY)
    string(REGEX MATCHALL "\\[libpxr_[A-Za-z0-9_]+\\.so\\]" needed "${dyn}")
    set(deps "")
    foreach(n ${needed})
        string(REGEX REPLACE "\\[libpxr_(.*)\\.so\\]" "\\1" n "${n}")
        list(APPEND deps ${n})
    endforeach()
    string(APPEND PXR_TARGET_DEFS
        "_pxr_add_target(${name} \"${lib}\" \"${deps}\")\n")
    list(APPEND PXR_TARGET_NAMES ${name})
endforeach()
configure_file(pxrConfig.cmake.in pxrConfig.cmake @ONLY)
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/pxrConfig.cmake DESTINATION lib/cmake/pxr)

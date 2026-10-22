# cmake -DPATCHELF=<patchelf> -DGLOB=<glob> [-DEXTRA_DIRS=<dir;dir>] -P set_runpath.cmake
#
# Sets RUNPATH to "$ORIGIN[:extra dirs]" on every regular file matching GLOB
# (symlinks are skipped; they point at the files being patched).

file(GLOB files "${GLOB}")
if(NOT files)
    message(FATAL_ERROR "set_runpath: nothing matches ${GLOB}")
endif()

set(runpath "$ORIGIN")
foreach(dir ${EXTRA_DIRS})
    string(APPEND runpath ":${dir}")
endforeach()

foreach(file ${files})
    if(NOT IS_SYMLINK "${file}")
        execute_process(COMMAND "${PATCHELF}" --set-rpath "${runpath}" "${file}"
                        COMMAND_ERROR_IS_FATAL ANY)
        message(STATUS "RUNPATH ${runpath}: ${file}")
    endif()
endforeach()

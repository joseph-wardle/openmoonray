# OpenMoonRay for Houdini 21 on EL9

Builds OpenMoonRay so it runs inside SideFX Houdini 21.0.596 (Solaris, husk)
on RHEL/Rocky/Alma 9, with no root access and no system `-devel` packages.

```bash
git submodule update --init --recursive
building/houdini21/build.sh --prefix /groups/sandwich/06_software/openmoonray/<name>
```

Then point Houdini at `<prefix>/houdini/moonray.json` (a Houdini package). In
the Sandwich pipeline that is one `package_path` entry; see
`src/pipe/dcc/houdini/site/packages/moonray.json` there.

Use a local disk for `--work` (default `$TMPDIR`). A full build from nothing,
downloads included, takes about 15 minutes on 32 cores and installs ~1.2 GB.

## What you get

- `bin/moonray`, `hd_render`, … plus `deps/bin/maketx`, `oiiotool`, `idiff`
- Scalar, vectorized (AVX2) and XPU (OptiX GPU) execution modes
- OptiX and OpenImageDenoise (CPU or CUDA) denoising
- The Hydra delegate ("Moonray" in the viewport renderer menu and in husk)
- MoonRay tabs on the Render Settings, Render Geometry Settings, Light and
  Render Var LOPs
- 126 `DW_MOONRAY` shader VOPs (TAB menu > DW Moonray) and a
  **MoonRay Material Builder** (TAB menu > MoonRay, inside a Material Library)
- MaterialX pattern nodes as MoonRay maps (`BUILD_MATERIALX_SHADERS`)

Not built: `moonray_gui` and `arras_render` (standalone Qt5 viewers; Houdini
only ships Qt6 and they are never loaded into Houdini).

## How it is put together

| File | Role |
|---|---|
| `build.sh` | The only entry point. Stages: `deps`, `moonray`, `post`. Re-runs itself in a scrubbed environment. |
| `deps/CMakeLists.txt` | Builds every third-party dependency from SHA-256-pinned sources. |
| `hfs/` | Generates CMake configs (`pxr`, `TBB`, `OpenImageDenoise`) and a header shim for the libraries we take from Houdini. |
| `moonray.cmake` | Initial cache for MoonRay's own configure: every input set explicitly. |
| `houdini/` | Our Houdini additions, copied into `<prefix>/plugin/houdini`. |
| `moonray_package.json.in` | The Houdini package written to `<prefix>/houdini/moonray.json`. |

### Which libraries come from Houdini

MoonRay runs inside Houdini's process, and a process can hold only one
library per soname. So:

- **Houdini's copy** of everything Houdini loads under the soname we would
  produce: USD 25.05, Python 3.11, oneTBB 2022, OpenImageDenoise 2.2,
  OpenSubdiv 3.6, blosc, jpeg, png, tiff, curl, freetype.
- **Our own build** of everything Houdini only ships renamed or namespaced
  (Boost→hboost, OpenImageIO/OpenEXR/Imath/OCIO→`*_sidefx`,
  OpenVDB→`*_sesi`, embree3), plus what Houdini lacks (embree 4, ISPC, CUDA
  runtime, OptiX 7.6 headers, Lua, log4cplus, jsoncpp, …).
- **The OS's copy** of system libraries (OpenSSL 3, zlib, libuuid, GL). We
  ship headers only where the labs lack `-devel` packages.

`$HFS/toolkit/include` is never put on the include path: it also contains
Houdini's OpenImageIO/OpenEXR/openvdb headers, which would silently shadow
ours. `hfs/` symlinks only the headers above.

The `post` stage checks every installed binary with `ldd` in a clean
environment and fails if anything is unresolved or resolves outside the
prefix, `$HFS` or the OS. If a build succeeds, the install does not depend
on the build machine.

## Changing versions

- **New Houdini build:** set `--hfs`. The deps build refuses a Houdini other
  than `ExpectedHoudiniVersion` (in `deps/CMakeLists.txt`) because USD, TBB
  and Python are ABI-coupled to it. Check those versions, then update the pin
  and `HFS` defaults, and build into a **new prefix**.
- **New MoonRay:** the submodules point at our forks' `houdini21` branches,
  which carry the Houdini fixes as ordinary commits on top of upstream.
  Rebase each branch onto the new upstream release, update the submodule
  pointers, and build into a new prefix.
- **A dependency:** change its URL and `URL_HASH` together.

Installs are not relocatable (RUNPATHs are absolute), and a prefix should
never be rebuilt in place once artists use it. Build a new prefix and switch
the pipeline's package path.

## Runtime notes

- Textures must be tiled and MIP-mapped (`maketx in.exr -o out.tx`). MoonRay
  rejects plain EXR/PNG/JPEG on purpose (`accept_untiled=false`).
- All geometry renders double-sided, as in RenderMan (`HDMOONRAY_DOUBLESIDED=1`
  in the package). Set `moonray:side_type` on a prim to override it.
- Houdini's GL viewport cannot draw MoonRay shaders; the Material Builder
  includes a UsdPreviewSurface for that.
- Hydra settings without a USD equivalent can be forced with environment
  variables (`HDMOONRAY_DEBUG`, `HDMOONRAY_INFO`, `HDMOONRAY_EXEC_MODE`, …);
  see `moonray/hydra/hdMoonray/README.md`.

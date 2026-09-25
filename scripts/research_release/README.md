# Reproducible Vivado release flow

This directory builds the canonical exact CFGLUT5/Dadda RTL in a fresh,
isolated Vivado project. The generated project is temporary; compact artifacts
can be published and checksum-verified before the project is removed.

## Qualified profiles

The five checked specs in `builds/` correspond to A32, B32, C32, D32, and
D640. Each uses the same generalized RTL and the 125 MHz clock constraint.

## New profiles

Create a separate, unqualified development profile with `create_profile.py`.
The current RTL supports N=3 or N=5, K=1..64, and compile-time width/height.
The generator checks the 22-bit DMA lengths and creates both the development
catalog entry and Tcl spec.

## Build workflow

```powershell
python -B scripts/research_release/research_release.py check A32_CFGLUT125
python -B scripts/research_release/research_release.py prepare A32_CFGLUT125
```

Run in the Vivado Tcl console:

```tcl
cd {D:/MyProjects/Convlution_Accelerator}
set research_release_id A32_CFGLUT125
source {scripts/research_release/research_build.tcl}
```

Then preserve the compact artifacts and remove the generated project:

```powershell
python -B scripts/research_release/research_release.py manifest A32_CFGLUT125
python -B scripts/research_release/research_release.py publish A32_CFGLUT125
python -B scripts/research_release/research_release.py clean A32_CFGLUT125 --yes
```

The build fails closed on catalog/spec identity, deterministic configuration
rendering, source presence, timing, DRC, route status, clock frequency, DMA
configuration, and release-ILA exclusion. `clean` requires `--yes` and refuses
to delete a generated tree unless the published checksum set verifies.

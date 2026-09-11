"""User-run check of six saved bitbake -e outputs; never invokes BitBake or app code."""
import argparse
from pathlib import Path
import re


def read(directory, name):
    text = (directory/(name+".env")).read_text(encoding="utf-8")
    return dict(re.findall(r'^([A-Za-z0-9_:+.-]+)="([^\n]*)"$', text, re.MULTILINE))


def need(condition, message):
    if not condition:
        raise ValueError(message)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", type=Path, required=True)
    args = parser.parse_args()
    configs = {x: read(args.directory, x) for x in
               ("python3", "python3-pillow", "conv-lab", "conv-lab-starter",
                "conv-lab-validation", "petalinux-image-minimal")}
    for name, data in configs.items():
        need(data.get("MACHINE") == "zynq-generic-7z020", name+": unexpected MACHINE")
        if name in ("python3", "python3-pillow", "petalinux-image-minimal"):
            need(data.get("TARGET_ARCH") == "arm", name+": target is not ARM")
        else:
            need(data.get("PACKAGE_ARCH") == "all" and data.get("TARGET_ARCH") == "allarch",
                 name+": expected architecture-independent package")
    py = configs["python3"]
    need(py.get("PV") == "3.12.11", "Python recipe version changed; review")
    need("python3-modules" in py.get("PACKAGES", "").split(), "python3-modules unavailable")
    for name in ("core", "ctypes", "fcntl", "resource", "unittest", "unixadmin", "compression", "json"):
        need("python3-"+name in py.get("RDEPENDS:python3-modules", "").split(), "module split absent: "+name)
    pillow = configs["python3-pillow"]
    need(pillow.get("PV") == "10.3.0", "Pillow recipe version changed; review")
    options = pillow.get("PEP517_BUILD_OPTS", "")
    need("jpeg=enable" in options and "zlib=enable" in options and
         "jpeg=disable" not in options and "zlib=disable" not in options, "PNG/JPEG configuration differs")
    for name in ("conv-lab", "conv-lab-starter", "conv-lab-validation"):
        data = configs[name]
        need(data.get("S") == data.get("WORKDIR") and bool(data.get("S")), "unpack root differs: "+name)
        need("/project-spec/meta-user/recipes-apps/"+name+"/" in data.get("FILE", ""), "unexpected recipe provider: "+name)
    need(configs["conv-lab"].get("LICENSE") == "CLOSED" and
         configs["conv-lab-validation"].get("LICENSE") == "CLOSED", "team license classification changed")
    need(configs["conv-lab-starter"].get("LICENSE") == "LicenseRef-ConvLab-Starter-Provenance-Unresolved",
         "starter provenance classification changed")
    for package in ("python3-core", "python3-modules", "python3-pillow"):
        need(package in configs["conv-lab"].get("RDEPENDS:conv-lab", "").split(), "missing runtime "+package)
    for package in ("conv-lab", "conv-lab-starter", "python3-modules"):
        need(package in configs["conv-lab-validation"].get("RDEPENDS:conv-lab-validation", "").split(),
             "missing validation dependency "+package)
    image = configs["petalinux-image-minimal"]
    selected = (image.get("IMAGE_INSTALL", "")+" "+image.get("PACKAGE_INSTALL", "")).split()
    need("conv-lab-validation" in selected, "validation package not selected in image")
    print("Evaluated settings match this stage. This is not a successful build or codec/runtime test.")


if __name__ == "__main__":
    main()

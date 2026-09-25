SUMMARY = "Authenticated browser control panel for the Conv Lab FPGA accelerator"
LICENSE = "CLOSED"
SRC_URI = "file://server.py file://static/ file://conv-lab-gui file://runtime/ file://profiles/ file://firmware/"
S = "${WORKDIR}"

inherit allarch update-rc.d

RDEPENDS:${PN} = "conv-lab conv-lab-starter conv-lab-classifier python3-core python3-modules python3-pillow"
INITSCRIPT_NAME = "conv-lab-gui"
INITSCRIPT_PARAMS = "defaults 95 05"

do_configure[noexec] = "1"
do_compile[noexec] = "1"

do_install() {
    install -d ${D}/opt/conv-lab-gui/static
    install -m 0755 ${S}/server.py ${D}/opt/conv-lab-gui/server.py
    install -m 0644 ${S}/static/index.html ${D}/opt/conv-lab-gui/static/
    install -m 0644 ${S}/static/app.css ${D}/opt/conv-lab-gui/static/
    install -m 0644 ${S}/static/app.js ${D}/opt/conv-lab-gui/static/
    install -m 0644 ${S}/static/favicon.svg ${D}/opt/conv-lab-gui/static/

    install -d ${D}${sysconfdir}/init.d
    install -m 0755 ${S}/conv-lab-gui ${D}${sysconfdir}/init.d/conv-lab-gui

    install -d ${D}/home/petalinux ${D}/home/petalinux/profiles
    install -m 0755 ${S}/runtime/m4_filebackend.py ${S}/runtime/m7_switch.py ${S}/runtime/m8_cli.py ${D}/home/petalinux/
    cp -R --no-preserve=ownership ${S}/profiles/. ${D}/home/petalinux/profiles/
    find ${D}/home/petalinux/profiles -type d -exec chmod 0755 {} +
    find ${D}/home/petalinux/profiles -type f -exec chmod 0644 {} +

    install -d ${D}${nonarch_base_libdir}/firmware
    install -m 0644 ${S}/firmware/a32_cfglut125_125mhz.bit.bin ${D}${nonarch_base_libdir}/firmware/m7_A32_CFGLUT125.bin
    install -m 0644 ${S}/firmware/b32_cfglut125_125mhz.bit.bin ${D}${nonarch_base_libdir}/firmware/m7_B32_CFGLUT125.bin
    install -m 0644 ${S}/firmware/c32_cfglut125_125mhz.bit.bin ${D}${nonarch_base_libdir}/firmware/m7_C32_CFGLUT125.bin
    install -m 0644 ${S}/firmware/d32_cfglut125_125mhz.bit.bin ${D}${nonarch_base_libdir}/firmware/m7_D32_CFGLUT125.bin
    install -m 0644 ${S}/firmware/d640_cfglut125_125mhz.bit.bin ${D}${nonarch_base_libdir}/firmware/m7_D640_CFGLUT125.bin

}

FILES:${PN} = "${sysconfdir}/init.d/conv-lab-gui /opt/conv-lab-gui /home/petalinux/m4_filebackend.py /home/petalinux/m7_switch.py /home/petalinux/m8_cli.py /home/petalinux/profiles ${nonarch_base_libdir}/firmware/m7_A32_CFGLUT125.bin ${nonarch_base_libdir}/firmware/m7_B32_CFGLUT125.bin ${nonarch_base_libdir}/firmware/m7_C32_CFGLUT125.bin ${nonarch_base_libdir}/firmware/m7_D32_CFGLUT125.bin ${nonarch_base_libdir}/firmware/m7_D640_CFGLUT125.bin"

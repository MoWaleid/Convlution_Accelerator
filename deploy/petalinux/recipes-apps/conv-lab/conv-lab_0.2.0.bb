# Finalized for user-run PetaLinux 2025.2 application/build; not executed.
SUMMARY = "Conv Lab exact offline reference and bounded decoder"
LICENSE = "CLOSED"
SRC_URI = "file://conv_lab/ file://documentation/ file://launch.py file://conv-lab-offline file://conv-lab-prepare-output"
S = "${WORKDIR}"
inherit allarch
RDEPENDS:${PN} = "python3-core python3-modules python3-pillow"
do_configure[noexec] = "1"
do_compile[noexec] = "1"
do_install() {
    install -d ${D}/opt/conv-lab/app/conv_lab ${D}/opt/conv-lab/documentation
    install -m 0644 ${S}/conv_lab/*.py ${D}/opt/conv-lab/app/conv_lab/
    install -m 0644 ${S}/launch.py ${D}/opt/conv-lab/app/launch.py
    install -m 0644 ${S}/documentation/* ${D}/opt/conv-lab/documentation/
    install -d ${D}${bindir} ${D}${sbindir} ${D}/var/lib/conv-lab
    install -m 0755 ${S}/conv-lab-offline ${D}${bindir}/conv-lab-offline
    install -m 0755 ${S}/conv-lab-prepare-output ${D}${sbindir}/conv-lab-prepare-output
    chmod 0755 ${D}/var/lib/conv-lab
}
FILES:${PN} = "/opt/conv-lab/app/conv_lab /opt/conv-lab/app/launch.py /opt/conv-lab/documentation ${bindir}/conv-lab-offline ${sbindir}/conv-lab-prepare-output /var/lib/conv-lab"

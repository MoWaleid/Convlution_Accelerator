SUMMARY = "Native PS tail for FPGA-first CIFAR-10 classification"
LICENSE = "CLOSED"

SRC_URI = "file://ps_tail_runtime.cpp file://bundle/"
S = "${WORKDIR}"

do_compile() {
    ${CXX} ${CPPFLAGS} ${CXXFLAGS} -std=c++14 -O3 \
        ${S}/ps_tail_runtime.cpp -o conv-classify-tail ${LDFLAGS}
}

do_install() {
    install -d ${D}${bindir} ${D}/opt/conv-lab-classifier/B32_CFGLUT125
    install -m 0755 ${B}/conv-classify-tail ${D}${bindir}/conv-classify-tail
    install -m 0644 ${S}/bundle/* ${D}/opt/conv-lab-classifier/B32_CFGLUT125/
}

FILES:${PN} = "${bindir}/conv-classify-tail /opt/conv-lab-classifier"

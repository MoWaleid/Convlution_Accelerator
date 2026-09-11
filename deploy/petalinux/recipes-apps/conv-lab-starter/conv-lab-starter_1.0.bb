# Finalized for user-run PetaLinux 2025.2 application/build; not executed.
SUMMARY = "Preserved converted trained model and single-image dataset"
LICENSE = "LicenseRef-ConvLab-Starter-Provenance-Unresolved"
LIC_FILES_CHKSUM = "file://PROVENANCE-NOTICE.txt;md5=580d2da4b9c8f02590d450632d2fe2e7"
SRC_URI = "file://model/ file://dataset/ file://PROVENANCE-NOTICE.txt"
S = "${WORKDIR}"
inherit allarch
do_configure[noexec] = "1"
do_compile[noexec] = "1"
do_install() {
    install -d ${D}/opt/conv-lab/provenance
    install -m 0644 ${S}/PROVENANCE-NOTICE.txt ${D}/opt/conv-lab/provenance/starter-NOTICE.txt
    model=${D}/opt/conv-lab/library/models/N3_K8/m0-trained-cifar-k8/converted-1
    dataset=${D}/opt/conv-lab/library/datasets/m0-cifar-cat/converted-1
    install -d $model/weights $dataset/images
    install -m 0644 ${S}/model/model.json ${S}/model/channel_config.json $model/
    install -m 0644 ${S}/model/weights/*.mem $model/weights/
    install -m 0644 ${S}/dataset/dataset.json $dataset/
    install -m 0644 ${S}/dataset/images/*.png $dataset/images/
}
FILES:${PN} = "/opt/conv-lab/provenance/starter-NOTICE.txt /opt/conv-lab/library/models/N3_K8/m0-trained-cifar-k8/converted-1 /opt/conv-lab/library/datasets/m0-cifar-cat/converted-1"

# Local provenance identifier, not a license grant. Preserve upstream asset limitations.

NO_GENERIC_LICENSE[LicenseRef-ConvLab-Starter-Provenance-Unresolved] = "PROVENANCE-NOTICE.txt"

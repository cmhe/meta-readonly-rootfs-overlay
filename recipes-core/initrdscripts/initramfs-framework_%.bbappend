do_install_append () {
    rm ${D}/init
}

FILES_${PN}_remove = "/init"

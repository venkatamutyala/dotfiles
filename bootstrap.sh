#!/bin/bash


echo '

debugbusybox() {
    kubectl run -i --tty --rm busybox --image=busybox --restart=Never -- sh
}

debugubuntu() {
    kubectl run -i --tty --rm busybox --image=busybox --restart=Never -- sh
}
' >> /home/vscode/.bashrc

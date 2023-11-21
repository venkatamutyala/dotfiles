#!/bin/bash


echo '

debug-busybox() {
    kubectl run -i --tty --rm busybox --image=busybox --restart=Never -- sh
}

debug-ubuntu() {
    kubectl run -i --tty --rm busybox --image=ubuntu --restart=Never -- sh
}

' >> /home/vscode/.bashrc

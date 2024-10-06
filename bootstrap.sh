#!/bin/bash


mkdir -p ~/.oh-my-zsh/custom/plugins/my-debug-functions

echo '
debug-busybox() {
    kubectl run -i --tty --rm busybox --image=busybox --restart=Never -- sh
}

debug-ubuntu() {
    kubectl run -i --tty --rm busybox --image=ubuntu --restart=Never -- sh
}
' > ~/.oh-my-zsh/custom/plugins/my-debug-functions/my-debug-functions.plugin.zsh



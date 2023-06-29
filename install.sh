#!/bin/bash

COL_RED='\033[0;31m'
COL_BLUE='\033[1;34m'
COL_GREEN='\033[0;32m'
COL_YELLOW='\033[0;33m'
COL_RESET='\033[0m'


clear

if [  -d "/home/$USER/.cleansweep" ]
then
    rm -R /home/$USER/.cleansweep
fi

    if [ "$(id -u)" -ne "0" ]
    then
        echo -e "${COL_YELLOW}Sudo permission required! (It's Safe)${COL_RESET}\n"
        sudo ls
        clear
    fi

    if ! [ $(rmlint) ]
    then
        yes | sudo pacman -S rmlint
#        clear
    fi

    if ! [ $(gum) ]
    then
        yes | sudo pacman -S gum
#        clear
    fi

    if ! shc -C 2>/dev/null
    then
        git clone https://aur.archlinux.org/shc.git
        cd shc
        makepkg -si
        cd ..
    fi
    #echo "Hello"
    sudo shc -f program.sh
    mkdir /home/$USER/.cleansweep/
    cp program.sh.x /home/$USER/.cleansweep/cleansweep
    chmod 740 /home/$USER/.cleansweep/cleansweep
    if ! grep -Fxq "PATH=\$PATH:/home/$USER/.cleansweep" /home/$USER/.bashrc
    then
        export PATH=$PATH:/home/$USER/.cleansweep
        echo "PATH=\$PATH:/home/$USER/.cleansweep" >> /home/$USER/.bashrc
    fi
    clear
    echo -e "\n ${COL_GREEN}Installation Successfull!${COL_RESET}"
    echo -e "Command to use CleanSweap : ${COL_YELLOW}cleansweep${COL_RESET}\n"
#clear


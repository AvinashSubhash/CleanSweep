#!/bin/bash

COL_RED='\033[0;31m'
COL_BLUE='\033[1;34m'
COL_GREEN='\033[0;32m'
COL_YELLOW='\033[0;33m'
COL_RESET='\033[0m'

if [ "$(id -u)" -ne "0" ]
then
    echo -e "${COL_YELLOW}Sudo permission required! (It's Safe)${COL_RESET}\n"
    sudo ls
    clear
fi

if [ $(rmlint) ]
then
    echo ""
else
    yes | sudo pacman -S rmlint
    clear
fi

if [ $(gum) ]
then
    echo ""
else
    yes | sudo pacman -S gum
    clear
fi

sudo mv program.sh.x /usr/bin/cleansweep
sudo chmod 777 /usr/bin/cleansweep 
#clear
echo -e "\n ${COL_GREEN}Installation Successfull!${COL_RESET}"
echo -e "Command to use CleanSweap : ${COL_YELLOW}cleansweep${COL_RESET}\n"

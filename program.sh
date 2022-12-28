#!/bin/sh
COL_RED='\033[0;31m'
COL_BLUE='\033[1;34m'
COL_GREEN='\033[0;32m'
COL_YELLOW='\033[0;33m'
COL_RESET='\033[0m'

clear

if [ "$(id -u)" -ne "0" ]
then
    sudo ls
    clear
fi

echo -e "${COL_BLUE}Welcome to CleanSweep!${COL_RESET}"
echo ""
echo -e "${COL_YELLOW}Stage 1: Cleaning package manager's Cache${COL_RESET}"
echo -e "${COL_GREEN}\nCurrent Cache Size : ${COL_RED}$(sudo du -sh /var/cache/pacman/pkg/ | grep -Po [0-9]+"."*[0-9]*[MG])\n${COL_RESET}"
option=$(gum choose "Remove uninstalled module's package" "Remove all package" "Skip")
if [ "$option" == "Remove uninstalled module's package" ]
then 
    gum spin --title="Cleaning Cache . ." sleep 2
    echo "pacman -Sc"
elif [ "$option" == "Remove all package" ]
then
    gum spin --title="Cleaning Cache . ." sleep 2
    echo "pacman -Scc"
else
    echo "Skipped"
fi
echo ""
gum spin --title="Moving to step 2 . ." sleep 2
clear


# Step 2 - Removing unused packages

echo -e "Stage 2: Removing unused packages\n"
echo -e "\nList of unused packages : \n\n $(sudo pacman -Qtdq)\n"
option=$(gum choose "Remove unused modules" "Skip")
if [ "$option" == "Remove unused modules" ]
then 
    gum spin --title="Removing the modules . ." sleep 2
    echo "sudo pacman -Rns \$(sudo pacman -Qtdq)"
else
    echo "Skipped"
fi
echo ""
gum spin --title="Moving to step 3 . ." sleep 2
clear

# Step 3 - Cleaning cache in home directory

echo -e "Stage 3: Cleaning cache in home directory\n"
echo -e "\nSize of cache : \n\n $(sudo du -sh ~/.cache/ | grep -Po [0-9]+"."*[0-9]*[MG])\n"
option=$(gum choose "Clean cache" "Skip")
if [ "$option" == "Clean cache" ]
then 
    gum spin --title="Cleaning cache . ." sleep 2
    echo "rm -rf ~/.cache/"
else
    echo "Skipped"
fi
echo ""
gum spin --title="Moving to step 4 . ." sleep 2
clear

# Step 4 - Remove duplicate files

echo -e "Stage 4: Removing duplicate files\n"
option=$(gum choose "Remove duplicate files" "Skip")
if [ "$option" == "Remove duplicate files" ]
then
    rmlint /home/$USER
    gum spin --title="Removind duplicates . ." sleep 2
    echo "sh -c rmlint.sh"
else
    echo "Skipped"
fi
echo ""
gum spin --title="Moving to step 4 . ." sleep 2
clear

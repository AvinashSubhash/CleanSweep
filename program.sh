#!/bin/sh
COL_RED='\033[0;31m'
COL_BLUE='\033[1;34m'
COL_GREEN='\033[0;32m'
COL_YELLOW='\033[0;33m'
COL_RESET='\033[0m'

clear

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






echo -e "${COL_BLUE}Welcome to CleanSweep!${COL_RESET}"
echo ""
echo -e "${COL_YELLOW}Stage 1: Cleaning package manager's Cache${COL_RESET}"
echo -e "${COL_GREEN}\nCurrent Cache Size : ${COL_RED}$(sudo du -sh /var/cache/pacman/pkg/ | grep -Po [0-9]+"."*[0-9]*[MG])\n${COL_RESET}"
option=$(gum choose "Remove uninstalled module's package" "Remove all package" "Skip")
if [ "$option" == "Remove uninstalled module's package" ]
then
    yes Y | sudo pacman -Sc
    gum spin --title="Cleaning Cache . ." sleep 2
    
elif [ "$option" == "Remove all package" ]
then
    yes Y | sudo pacman -Scc
    gum spin --title="Cleaning Cache . ." sleep 2
else 
    echo "Skipped"
fi
echo ""
gum spin --title="Moving to step 2 . ." sleep 2
clear


# Step 2 - Removing unused packages

echo -e "${COL_YELLOW}Stage 2: Removing unused packages${COL_RESET}\n"
echo -e "\nList of unused packages : \n\n${COL_RED}$(sudo pacman -Qtdq)${COL_RESET}\n"
option=$(gum choose "Remove unused modules" "Skip")
if [ "$option" == "Remove unused modules" ]
then 
    yes | sudo pacman -Rns $(sudo pacman -Qtdq)
    echo ""
    gum spin --title="Removing the modules . ." sleep 2
else
    echo "Skipped"
fi
echo ""
gum spin --title="Moving to step 3 . ." sleep 2
clear

# Step 3 - Cleaning cache in home directory

echo -e "${COL_YELLOW}Stage 3: Cleaning cache in home directory${COL_RESET}\n"
echo -e "\n${COL_GREEN}Size of cache : ${COL_RED}$(sudo du -sh ~/.cache/ | grep -Po [0-9]+"."*[0-9]*[MG])${COL_RESET}\n"
option=$(gum choose "Clean cache" "Skip")
if [ "$option" == "Clean cache" ]
then 
    yes | sudo rm -rf /home/$USER/.cache/
    echo ""
    gum spin --title="Cleaning cache . ." sleep 2
else
    echo "Skipped"
fi
echo ""
gum spin --title="Moving to step 4 . ." sleep 2
clear

# Step 4 - Remove duplicate files

echo -e "${COL_YELLOW}Stage 4: Removing duplicate files${COL_RESET}\n"
option=$(gum choose "Remove duplicate files" "Skip")
if [ "$option" == "Remove duplicate files" ]
then
    rmlint /home/$USER
    echo ""
    sudo chmod 740 rmlint.sh
    yes | sudo sh rmlint.sh -c
    echo ""
    gum spin --title="Removind duplicates . ." sleep 2
else
    echo "Skipped"
fi
echo ""
gum spin --title="Moving to step 4 . ." sleep 2
clear

#Step - 5 Keeping log size limit for journalctl
echo -e "${COL_YELLOW}Stage 5: Setting log size limit${COL_RESET}\n"
echo -e "Do you want to set Log size limit ?\n" 
option=$(gum choose "Yes" "No")
if [ "$option" == "Yes" ]
then
    echo -e "Enter the size  ( Warning: Incorrect size format might cause Severe Problems! ) \nfor MegaBytes: <size>M, for GigaBytes: <Size>G: \n"
    opt1=$(gum write)
    echo -e "Selected size: $opt1\n"
    opt=$(gum choose "Proceed" "Cancel")
    if [ "$opt" == "Proceed" ]
    then
        sudo journalctl --vacuum-size=$opt1
        echo ""
        gum spin --title="Setting log size . ." sleep 2

    else
        echo -e "Step Cancelled\n"
    fi

else
    echo -e "Skipped\n"
fi

clear
echo -e "${COL_GREEN}Thank you for using CleanSweep!${COL_RESET}\n"
sleep 2
clear
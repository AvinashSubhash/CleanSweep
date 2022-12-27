clear
echo "Welcome to CleanSweep!"
echo ""
echo "Stage 1: Cleaning package manager's Cache"
option=$(gum choose "Remove uninstalled module's package" "Remove all package")
if [ "$option" == "Remove uninstalled module's package" ]
then 
    gum spin --title="Cleaning Cache . ." sleep 10
    echo "pacman -Sc"
else 
    gum spin --title="Cleaning Cache . ." sleep 10
    echo "pacman -Scc"
fi

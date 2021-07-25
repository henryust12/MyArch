#==============================================
# Bash Script
# Created by shima
# automaticly clear cache and unused pacman
#==============================================

yes | sudo pacman -Scc
yes | paru -Scc
sudo du -sh ~/.cache/
sudo rm -fr ~/.cache/*
du -sh /var/cache/pacman/pkg/
yes | sudo pacman -Rns $(pacman -Qtdq)
sudo paccache -r

#sleep 2

clear
echo " Finished "

# run sudo chmod a+x clear.sh, so we can run ./clear without any problem

x=$(ls list | head -n1)

sudo pacman -S --needed - < list/$x

#!/bin/bash

#timezones
timezones() {

	env_file=$1
	TZ=$(cat /etc/timezone)

	#test for TZ=
	[ $(grep -c "TZ=" $env_file) -ne 0 ] && sed -i "/TZ=/c\TZ=$TZ" $env_file

}

#future function add password in build phase
password_dialog() {
	while [[ "$passphrase" != "$passphrase_repeat" || ${#passphrase} -lt 8 ]]; do

		passphrase=$(whiptail --passwordbox "${passphrase_invalid_message}Please enter the passphrase (8 chars min.):" 20 78 3>&1 1>&2 2>&3)
		passphrase_repeat=$(whiptail --passwordbox "Please repeat the passphrase:" 20 78 3>&1 1>&2 2>&3)
		passphrase_invalid_message="Passphrase too short, or not matching! "
	done
	echo $passphrase
}
#test=$( password_dialog )

function command_exists() {
	command -v "$@" >/dev/null 2>&1
}

#function copies the template yml file to the local service folder and appends to the docker-compose.yml file
function yml_builder() {
	service="services/$1/service.yml"

	[ -d ./services/ ] || mkdir ./services/

	if [ -d ./services/$1 ]; then
		#directory already exists prompt user to overwrite
		sevice_overwrite=$(whiptail --radiolist --title "Overwrite Option" --notags \
			"$1 service directory has been detected, use [SPACEBAR] to select you overwrite option" 20 78 12 \
			"none" "Do not overwrite" "ON" \
			"env" "Preserve Environment and Config files" "OFF" \
			"full" "Pull full service from template" "OFF" \
			3>&1 1>&2 2>&3)

		case $sevice_overwrite in

		"full")
			echo "...pulled full $1 from template"
			rsync -a -q .templates/$1/ services/$1/ --exclude 'build.sh'
			;;
		"env")
			echo "...pulled $1 excluding env file"
			rsync -a -q .templates/$1/ services/$1/ --exclude 'build.sh' --exclude '$1.env' --exclude '*.conf'
			;;
		"none")
			echo "...$1 service not overwritten"
			;;

		esac

	else
		mkdir ./services/$1
		echo "...pulled full $1 from template"
		rsync -a -q .templates/$1/ services/$1/ --exclude 'build.sh'
	fi

	#if an env file exists check for timezone
	[ -f "./services/$1/$1.env" ] && timezones ./services/$1/$1.env

	cat $service >>docker-compose.yml

	#test for post build
	if [ -f ./.templates/$1/build.sh ]; then
		chmod +x ./.templates/$1/build.sh
		bash ./.templates/$1/build.sh
	fi

}

#---------------------------------------------------------------------------------------------------
# Menu system starts here
# Display main menu
mainmenu_selection=$(whiptail --title "Main Menu" --menu --notags \
	"" 20 78 12 -- \
	"install" "Install Docker" \
	"build" "Build Stack" \
	"hassio" "Install Hass.io (Requires Docker)" \
	"native" "Native Installs" \
	"commands" "Docker commands" \
	"backup" "Backup options" \
	"misc" "Miscellaneous commands" \
	"update" "Update my-pistack" \
	3>&1 1>&2 2>&3)

case $mainmenu_selection in
#MAINMENU Install docker  ------------------------------------------------------------
"install")
	#sudo apt update && sudo apt upgrade -y ;;

	if command_exists docker; then
		echo "docker already installed"
	else
		echo "Install Docker"
		curl -fsSL https://get.docker.com | sh
		sudo usermod -aG docker $USER
	fi

	if command_exists docker-compose; then
		echo "docker-compose already installed"
	else
		echo "Install docker-compose"
		sudo apt install -y docker-compose
	fi

	if (whiptail --title "Restart Required" --yesno "It is recommended that you restart you device now. Select yes to do so now" 20 78); then
		sudo reboot
	fi
	;;
	#MAINMENU Build stack ------------------------------------------------------------
"build")
	container_selection=$(whiptail --title "Container Selection" --notags --separate-output --checklist \
		"Use the [SPACEBAR] to select which containers you would like to install" 20 78 12 \
		"portainer" "Portainer" "ON" \
		"influxdb" "InfluxDB" "ON" \
		"postgres" "Postgres" "OFF" \
		"shiny" "shiny" "ON" \
		"adminer" "Adminer" "OFF" \
		3>&1 1>&2 2>&3)

	mapfile -t containers <<<"$container_selection"

	#if no container is selected then dont overwrite the docker-compose.yml file
	if [ -n "$container_selection" ]; then
		touch docker-compose.yml
		echo "version: '2'" >docker-compose.yml
		echo "services:" >>docker-compose.yml

		#Run yml_builder of all selected containers
		for container in "${containers[@]}"; do
			echo "Adding $container container"
			yml_builder "$container"
		done

		echo "docker-compose successfully created"
		echo "run 'docker-compose up -d' to start the stack"
	else
		echo "Build cancelled"

	fi
	;;
	#MAINMENU Docker commands -----------------------------------------------------------
"commands")

	docker_selection=$(
		whiptail --title "Docker commands" --menu --notags \
			"Shortcut to common docker commands" 20 78 12 -- \
			"aliases" "Add my-pistack_up and my-pistack_down aliases" \
			"start" "Start stack" \
			"restart" "Restart stack" \
			"stop" "Stop stack" \
			"stop_all" "Stop any running container regardless of stack" \
			"pull" "Update all containers" \
			"prune_volumes" "Delete all stopped containers and docker volumes" \
			"prune_images" "Delete all images not associated with container" \
			3>&1 1>&2 2>&3
	)

	case $docker_selection in
	"start") ./scripts/start.sh ;;
	"stop") ./scripts/stop.sh ;;
	"stop_all") ./scripts/stop-all.sh ;;
	"restart") ./scripts/restart.sh ;;
	"pull") ./scripts/update.sh ;;
	"prune_volumes") ./scripts/prune-volumes.sh ;;
	"prune_images") ./scripts/prune-images.sh ;;
	"aliases")
		touch ~/.bash_aliases
		if [ $(grep -c 'my-pistack' ~/.bash_aliases) -eq 0 ]; then
			echo ". ~/my-pistack/.bash_aliases" >>~/.bash_aliases
			echo "added aliases"
		else
			echo "aliases already added"
		fi
		source ~/.bashrc
		;;
	esac
	;;
	#Backup menu ---------------------------------------------------------------------
"backup")
	backup_sellection=$(whiptail --title "Backup Options" --menu --notags \
		"Select backup option" 20 78 12 -- \
		"dropbox-uploader" "Dropbox-Uploader" \
		"rclone" "google drive via rclone" \
		3>&1 1>&2 2>&3)

	case $backup_sellection in

	"dropbox-uploader")
		if [ ! -d ~/Dropbox-Uploader ]; then
			git clone https://github.com/andreafabrizi/Dropbox-Uploader.git ~/Dropbox-Uploader
			chmod +x ~/Dropbox-Uploader/dropbox_uploader.sh
			pushd ~/Dropbox-Uploader && ./dropbox_uploader.sh
			popd
		else
			echo "Dropbox uploader already installed"
		fi

		#add enable file for Dropbox-Uploader
		[ -d ~/my-pistack/backups ] || sudo mkdir -p ~/my-pistack/backups/
		sudo touch ~/my-pistack/backups/dropbox
		;;
	"rclone")
		sudo apt install -y rclone
		echo "Please run 'rclone config' to configure the rclone google drive backup"
		#add enable file for rclone
		[ -d ~/my-pistack/backups ] || sudo mkdir -p ~/my-pistack/backups/
		sudo touch ~/my-pistack/backups/rclone
		;;
	esac
	;;
	#MAINMENU Misc commands------------------------------------------------------------
"misc")
	misc_sellection=$(whiptail --title "Miscellaneous Commands" --menu --notags \
		"Some helpful commands" 20 78 12 -- \
		"swap" "Disable swap" \
		"log2ram" "install log2ram to decrease load on sd card, moves /var/log into ram" \
		3>&1 1>&2 2>&3)

	case $misc_sellection in
	"swap")
		sudo dphys-swapfile swapoff
		sudo dphys-swapfile uninstall
		sudo update-rc.d dphys-swapfile remove
		echo "Swap file has been removed"
		;;
	"log2ram")
		if [ ! -d ~/log2ram ]; then
			git clone https://github.com/azlux/log2ram.git ~/log2ram
			chmod +x ~/log2ram/install.sh
			pushd ~/log2ram && sudo ./install.sh
			popd
		else
			echo "log2ram already installed"
		fi
		;;
	esac
	;;

"hassio")
	echo "install requirements for hass.io"
	sudo apt install -y bash jq curl avahi-daemon dbus
	hassio_machine=$(whiptail --title "Machine type" --menu \
		"Please select you device type" 20 78 12 -- \
		"raspberrypi4" " " \
		"raspberrypi3" " " \
		"raspberrypi2" " " \
		"raspberrypi4-64" " " \
		"raspberrypi3-64" " " \
		"qemux86" " " \
		"qemux86-64" " " \
		"qemuarm" " " \
		"qemuarm-64" " " \
		"orangepi-prime" " " \
		"odroid-xu" " " \
		"odroid-c2" " " \
		"intel-nuc" " " \
		"tinker" " " \
		3>&1 1>&2 2>&3)
	if [ -n "$hassio_machine" ]; then
		curl -sL https://raw.githubusercontent.com/home-assistant/hassio-installer/master/hassio_install.sh | sudo bash -s -- -m $hassio_machine
	else
		echo "no selection"
		exit
	fi
	;;
"update")
	echo "Pulling latest project file from Github.com ---------------------------------------------"
	git pull origin master
	echo "git status ------------------------------------------------------------------------------"
	git status
	;;
"native")

	native_selections=$(whiptail --title "Native installs" --menu --notags \
		"Install local applications" 20 78 12 -- \
		"rtl_433" "RTL_433" \
		3>&1 1>&2 2>&3)

	case $native_selections in
	"rtl_433")
		bash ./.native/rtl_433.sh
		;;
	esac
	;;
*) ;;

esac

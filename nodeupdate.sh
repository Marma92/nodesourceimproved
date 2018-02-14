#!/bin/bash

######################################
# NodeUpdate
# Script to install the NodeSource Node.js v8.x
# repo onto a Debian or Ubuntu system.
# Authors : Amram Elbaz & Dorine Niel
# Last Update : 28/07/2016
######################################

export DEBIAN_FRONTEND=noninteractive
NODENAME="Node.js v8.x"
NODEREPO="node_8.x"
NODEPKG="nodejs"

print_status() {
    echo
    echo "## $1"
    echo
}

if test -t 1; then # if terminal
    ncolors=$(which tput > /dev/null && tput colors) # supports color
    if test -n "$ncolors" && test $ncolors -ge 8; then
        termcols=$(tput cols)
        bold="$(tput bold)"
        underline="$(tput smul)"
        standout="$(tput smso)"
        normal="$(tput sgr0)"
        black="$(tput setaf 0)"
        red="$(tput setaf 1)"
        green="$(tput setaf 2)"
        yellow="$(tput setaf 3)"
        blue="$(tput setaf 4)"
        magenta="$(tput setaf 5)"
        cyan="$(tput setaf 6)"
        white="$(tput setaf 7)"
    fi
fi


print_bold() {
    title="$1"
    text="$2"

    echo
    echo "${red}================================================================================${normal}"
    echo "${red}================================================================================${normal}"
    echo
    echo -e "  ${bold}${yellow}${title}${normal}"
    echo
    echo -en "  ${text}"
    echo
    echo "${red}================================================================================${normal}"
    echo "${red}================================================================================${normal}"
}

bail() {
    echo 'Error executing command, exiting'
    exit 1
}

exec_cmd_nobail() {
    echo "+ $1"
    bash -c "$1"
}

exec_cmd() {
    exec_cmd_nobail "$1" || bail
}


script_sudo_warning() {

	if [ "$EUID" -ne 0 ]; then
			print_bold \
"                            WARNING!                              " "\
${bold}This script need to be executed as administrator${normal}
  ${bold}You did not launch it as admin, and the script will shut down in 5 seconds${normal}.

	relaunch it as administrator.
"
	echo
        echo "Closing in 5 seconds ... (Ctrl-C to kill)"
        echo
        sleep 5
        exit

	fi

}


restart_services(){
	pm2 restart
	service nginx restart
}


node_deprecation_warning() {
    if [[ "X${NODENAME}" == "Xio.js v1.x" ||
          "X${NODENAME}" == "Xio.js v2.x" ||
          "X${NODENAME}" == "Xio.js v3.x" ||
          "X${NODENAME}" == "XNode.js v5.x" ]]; then

        print_bold \
"                            DEPRECATED!                           " "\
${bold}${NODENAME} is no longer actively supported!${normal}
  ${bold}You will not receive security or critical stability updates${normal} for this version.
  You should update to a new version of Node.js as soon as possible.
"
        echo
        echo "Continuing in 10 seconds ..."
        echo
        sleep 10

    elif [ "X${NODENAME}" == "XNode.js v0.10" ]; then

        print_bold \
"                     NODE.JS v0.10 DEPRECATION WARNING                      " "\
Node.js v0.10 will cease to be actively supported in ${bold}October 2016${normal}.
"

        echo
        echo "Continuing in 5 seconds ..."
        echo
        sleep 5

    elif [ "X${NODENAME}" == "XNode.js v0.12" ]; then

        print_bold \
"                     NODE.JS v0.12 DEPRECATION WARNING                      " "\
Node.js v0.12 will cease to be actively supported ${bold}at the end of 2016${normal}.
"

        echo
        echo "Continuing in 3 seconds ..."
        echo
        sleep 3

    fi
}


node_arm6_setup() {
	#TODO: make the link dynamic to dl the last version everytime
	print_status "Getting pre-compiled files for ARMv6 from NodeJS.org"
	exec_cmd "wget https://nodejs.org/dist/v7.1.0/node-v7.1.0-linux-armv6l.tar.xz"
	exec_cmd "tar xJvf ~/node-v7.1.0-linux-armv6l.tar.xz --strip=1"
}



server_install() {
	print_status "Installing nginx server"
	exec_cmd "apt-get install nginx"

	print_status "Now installing PM2 for a best gesture of your node apps"
	exec_cmd "npm install pm2 -g"
}

server_setting_up() {

	#add pm2 as a boot service
    pm2 startup

	#add a barebone node.js app
    if [ ! -d "/usr/local/nodeapps/" ];then
        exec_cmd "mkdir /usr/local/nodeapps/"
    fi

	#here write the node.js file
	echo > /usr/local/nodeapps/itworks.js "
			var http = require('http');
		http.createServer(function (req, res) {
			res.writeHead(200, {'Content-Type': 'text/plain'});
			res.end('Hello World\n');
		}).listen(8080);
		console.log('Server running at port 8080');
	"

	#warn that nginx settings will be overwritten
	exec_cmd_nobail "mv /etc/nginx/sites-available/default /etc/nginx/sites-available/default.old"
	echo > /etc/nginx/sites-available/default " server {
    listen 80;
    server_name localhost;
    location / {
        proxy_pass localhost:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
		}
	} "

	#prepared nginx available-sites file for reverse proxy

	#launch our node app with pm2
	exec_cmd_nobail "pm2 start /usr/local/nodeapps/itworks.js"
}

setup() {

script_sudo_warning


print_status "Installing the NodeSource ${NODENAME} repo..."

if $(uname -m | grep -Eq ^armv6); then
    print_status "You appear to be running on ARMv6 hardware. Let's go differently!"
    node_arm6_setup
else

	PRE_INSTALL_PKGS=""

	# Check that HTTPS transport is available to APT
	# (Check snaked from: https://get.docker.io/ubuntu/)

	if [ ! -e /usr/lib/apt/methods/https ]; then
		PRE_INSTALL_PKGS="${PRE_INSTALL_PKGS} apt-transport-https"
	fi

	if [ ! -x /usr/bin/lsb_release ]; then
		PRE_INSTALL_PKGS="${PRE_INSTALL_PKGS} lsb-release"
	fi

	if [ ! -x /usr/bin/curl ] && [ ! -x /usr/bin/wget ]; then
		PRE_INSTALL_PKGS="${PRE_INSTALL_PKGS} curl"
	fi

	# Populating Cache
	print_status "Populating apt-get cache..."
	exec_cmd 'apt-get update'

	if [ "X${PRE_INSTALL_PKGS}" != "X" ]; then
		print_status "Installing packages required for setup:${PRE_INSTALL_PKGS}..."
		# This next command needs to be redirected to /dev/null or the script will bork
		# in some environments
		exec_cmd "apt-get install -y${PRE_INSTALL_PKGS} > /dev/null 2>&1"
	fi

	IS_PRERELEASE=$(lsb_release -d | grep 'Ubuntu .*development' >& /dev/null; echo $?)
	if [[ $IS_PRERELEASE -eq 0 ]]; then
		print_status "Your distribution, identified as \"$(lsb_release -d -s)\", is a pre-release version of Ubuntu. NodeSource does not maintain official support for Ubuntu versions until they are formally released. You can try using the manual installation instructions available at https://github.com/nodesource/distributions and use the latest supported Ubuntu version name as the distribution identifier, although this is not guaranteed to work."
		exit 1
	fi

	DISTRO=$(lsb_release -c -s)

	check_alt() {
		if [ "X${DISTRO}" == "X${2}" ]; then
			echo
			echo "## You seem to be using ${1} version ${DISTRO}."
			echo "## This maps to ${3} \"${4}\"... Adjusting for you..."
			DISTRO="${4}"
		fi
	}

	check_alt "Kali"          "sana"     "Debian" "jessie"
	check_alt "Kali"          "kali-rolling" "Debian" "jessie"
	check_alt "Debian"        "stretch"  "Debian" "jessie"
	check_alt "Linux Mint"    "maya"     "Ubuntu" "precise"
	check_alt "Linux Mint"    "qiana"    "Ubuntu" "trusty"
	check_alt "Linux Mint"    "rafaela"  "Ubuntu" "trusty"
	check_alt "Linux Mint"    "rebecca"  "Ubuntu" "trusty"
	check_alt "Linux Mint"    "rosa"     "Ubuntu" "trusty"
	check_alt "Linux Mint"    "sarah"    "Ubuntu" "xenial"
	check_alt "LMDE"          "betsy"    "Debian" "jessie"
	check_alt "elementaryOS"  "luna"     "Ubuntu" "precise"
	check_alt "elementaryOS"  "freya"    "Ubuntu" "trusty"
	check_alt "elementaryOS"  "loki"     "Ubuntu" "xenial"
	check_alt "Trisquel"      "toutatis" "Ubuntu" "precise"
	check_alt "Trisquel"      "belenos"  "Ubuntu" "trusty"
	check_alt "BOSS"          "anokha"   "Debian" "wheezy"
	check_alt "bunsenlabs"    "bunsen-hydrogen" "Debian" "jessie"
	check_alt "Tanglu"        "chromodoris" "Debian" "jessie"

	if [ "X${DISTRO}" == "Xdebian" ]; then
	  print_status "Unknown Debian-based distribution, checking /etc/debian_version..."
	  NEWDISTRO=$([ -e /etc/debian_version ] && cut -d/ -f1 < /etc/debian_version)
	  if [ "X${NEWDISTRO}" == "X" ]; then
		print_status "Could not determine distribution from /etc/debian_version..."
	  else
		DISTRO=$NEWDISTRO
		print_status "Found \"${DISTRO}\" in /etc/debian_version..."
	  fi
	fi

	print_status "Confirming \"${DISTRO}\" is supported..."

	if [ -x /usr/bin/curl ]; then
		exec_cmd_nobail "curl -sLf -o /dev/null 'https://deb.nodesource.com/${NODEREPO}/dists/${DISTRO}/Release'"
		RC=$?
	else
		exec_cmd_nobail "wget -qO /dev/null -o /dev/null 'https://deb.nodesource.com/${NODEREPO}/dists/${DISTRO}/Release'"
		RC=$?
	fi

	if [[ $RC != 0 ]]; then
		print_status "Your distribution, identified as \"${DISTRO}\", is not currently supported, please contact NodeSource at https://github.com/nodesource/distributions/issues if you think this is incorrect or would like your distribution to be considered for support"
		exit 1
	fi

	if [ -f "/etc/apt/sources.list.d/chris-lea-node_js-$DISTRO.list" ]; then
		print_status 'Removing Launchpad PPA Repository for NodeJS...'

		exec_cmd_nobail 'add-apt-repository -y -r ppa:chris-lea/node.js'
		exec_cmd "rm -f /etc/apt/sources.list.d/chris-lea-node_js-${DISTRO}.list"
	fi

	print_status 'Adding the NodeSource signing key to your keyring...'

	if [ -x /usr/bin/curl ]; then
		exec_cmd 'curl -s https://deb.nodesource.com/gpgkey/nodesource.gpg.key | apt-key add -'
	else
		exec_cmd 'wget -qO- https://deb.nodesource.com/gpgkey/nodesource.gpg.key | apt-key add -'
	fi

	print_status "Creating apt sources list file for the NodeSource ${NODENAME} repo..."

	exec_cmd "echo 'deb https://deb.nodesource.com/${NODEREPO} ${DISTRO} main' > /etc/apt/sources.list.d/nodesource.list"
	exec_cmd "echo 'deb-src https://deb.nodesource.com/${NODEREPO} ${DISTRO} main' >> /etc/apt/sources.list.d/nodesource.list"

	print_status 'Running `apt-get update` for you...'

	exec_cmd 'apt-get update'

	node_deprecation_warning

	print_status "Now running \`apt-get install ${NODEPKG}\` (as root) to install ${NODENAME} and npm"

	exec_cmd "apt-get install ${NODEPKG}"
fi

print_status "Now will install the tools you need to set up your server"

server_install

server_setting_up

restart_services
}

## Defer setup until we have the complete script
setup

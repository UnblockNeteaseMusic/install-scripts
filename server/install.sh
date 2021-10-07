#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
#
# Copyright (C) 2021 The UnblockNeteaseMusic Group
# Maintainer: Tianling Shen <i@cnsztl.eu.org>

# Color definition
DEFAULT_COLOR="\033[0m"
BLUE_COLOR="\033[36m"
GREEN_COLOR="\033[32m"
GREEN_BACK="\033[42;37m"
RED_COLOR="\033[31m"
YELLOW_COLOR="\033[33m"

# URL definition
UNM_SERV_GIT_REPO="https://github.com/UnblockNeteaseMusic/server"
UNM_SERV_SCRIPT_URL="https://raw.githubusercontent.com/UnblockNeteaseMusic/install-scripts/master/server/install.sh"

# File definition
UNM_SERV_BIN_DIR="/usr/local/bin/unblockneteasemusic-server"
UNM_SERV_CONF_DIR="/usr/local/etc/unblockneteasemusic-server"
UNM_SERV_BIN="/usr/local/bin/unm-server"
UNM_SERV_ENV="${UNM_SERV_CONF_DIR}/unm-environments"
UNM_SERV_SERVICE="/etc/systemd/system/unblockneteasemusic-server.service"

function __error_msg() {
	echo -e "${RED_COLOR}[ERROR]${DEFAULT_COLOR} $1"
}

function __info_msg() {
	echo -e "${BLUE_COLOR}[INFO]${DEFAULT_COLOR} $1"
}

function __success_msg() {
	echo -e "${GREEN_COLOR}[SUCCESS]${DEFAULT_COLOR} $1"
}

function __warning_msg() {
	echo -e "${YELLOW_COLOR}[WARNING]${DEFAULT_COLOR} $1"
}

function base_check() {
	[ "${EUID}" -ne "0" ] && { __error_msg "请使用 ROOT 权限执行本脚本。"; exit 1; }
	command -v "systemctl" > "/dev/null" || { __error_msg "未在您的系统上发现 systemd，安装无法继续。"; exit 1; }

	if [ "$(uname -m)" != "x86_64" ] && [ "$(uname -m)" != "aarch64" ]; then
		__error_msg "目前暂不支持您所使用的架构：$(uname -m)。"
		exit 1
	fi

	if [ -e "/etc/redhat-release" ]; then
		SYSTEM_OS="RHEL"
	elif grep -Eq "(Debian||Deepin||Ubuntu)" "/etc/issue"; then
		SYSTEM_OS="DEBIAN"
	else
		__error_msg "暂不支持您所使用的发行版。"
		exit 1
	fi
}

function print_menu(){
	local INSTALL_STATUS RUNNING_STATUS UNM_SERV_ADDR UNM_SERV_IP UNM_SERV_PAC UNM_SERV_PID

	if [ -d "${UNM_SERV_BIN_DIR}" ]; then
		INSTALL_STATUS="${GREEN_COLOR}已安装${DEFAULT_COLOR}"
		UNM_SERV_PID="$(systemctl show --property MainPID --value ${UNM_SERV_SERVICE##*/})"
		if [ -z "${UNM_SERV_PID}" ] || [ "${UNM_SERV_PID}" == "0" ]; then
			RUNNING_STATUS="${RED_COLOR}未在运行${DEFAULT_COLOR}"
			UNM_SERV_ADDR="${RUNNING_STATUS}"
			UNM_SERV_PAC="${RUNNING_STATUS}"
		else
			source "$UNM_SERV_ENV"
			RUNNING_STATUS="${GREEN_COLOR}运行中${DEFAULT_COLOR} | ${GREEN_COLOR}PID: ${UNM_SERV_PID}${DEFAULT_COLOR}"
			UNM_SERV_IP="$(curl -fsSL "https://myip.ipip.net/s" || curl -fsSL "https://ipinfo.io/ip" || echo "127.0.0.1")"
			UNM_SERV_ADDR="${GREEN_BACK}${UNM_SERV_IP}:${PORTS}${DEFAULT_COLOR}"
			UNM_SERV_PAC="${GREEN_BACK}http://${UNM_SERV_IP}:${PORTS%:*}/proxy.pac${DEFAULT_COLOR}"
		fi
	else
		INSTALL_STATUS="${RED_COLOR}未安装${DEFAULT_COLOR}"
		RUNNING_STATUS="${INSTALL_STATUS}"
		UNM_SERV_ADDR="${INSTALL_STATUS}"
		UNM_SERV_PAC="${INSTALL_STATUS}"
	fi

	echo -e "UnblockNeteaseMusic 服务端安装状态：${INSTALL_STATUS}
UnblockNeteaseMusic 服务端运行状态：${RUNNING_STATUS}
----------------------------------------------
	1. 安装 UnblockNeteaseMusic 服务端
	2. 移除 UnblockNeteaseMusic 服务端

	3. 启动/停止 UnblockNeteaseMusic 服务端
	4. 重启 UnblockNeteaseMusic 服务端

	5. 调整 UnblockNeteaseMusic 服务端设定
	6. 手动更新 UnblockNeteaseMusic 服务端
----------------------------------------------
UnblockNeteaseMusic 服务端监听地址: ${UNM_SERV_ADDR}
UnblockNeteaseMusic 服务端自动代理文件地址: ${UNM_SERV_PAC}
----------------------------------------------"
	local DO_ACTION
	read -rep "Action [1-6]: " DO_ACTION
	case "${DO_ACTION}" in
		"1") install_unm_server ;;
		"2") remove_unm_server ;;
		"3") start_stop_unm_server ;;
		"4") restart_unm_server ;;
		"5") tweak_unm_server ;;
		"6") update_unm_server ;;
		"") __info_msg "操作已取消。"; exit 2 ;;
		*) __error_msg "未定义行为：${DO_ACTION}。"; exit 2 ;;
	esac
}

function install_unm_server() {
	if [ -f "${UNM_SERV_BIN_DIR}/.install-done" ]; then
		local REINSTALL_UNM_SERV
		__info_msg "您似乎已经安装过 UnblockNeteaseMusic 服务端。"
		read -rep "是否重新安装 [y/N]：" REINSTALL_UNM_SERV
		case "${REINSTALL_UNM_SERV}" in
		[yY][eE][sS]|[yY])
			__info_msg "正在移除现有安装。。。"
			remove_unm_server
			;;
		*)
			__error_msg "操作已取消。"
			exit 2
			;;
		esac
	else
		rm -rf "${UNM_SERV_BIN_DIR}"
	fi

	__info_msg "正在处理依赖项。。。"
	if [ "${SYSTEM_OS}" == "RHEL" ]; then
		yum update -y
		yum install -y epel-release
		yum install -y ca-certificates crontabs curl firewalld git lsof
		curl -fsSL "https://rpm.nodesource.com/setup_14.x" | bash
		yum install -y nodejs
		[ -e "/etc/ssh/sshd_config" ] && firewall-cmd --permanent --zone=public --add-port=$(awk -F 'Port ' '{print $2}' '/etc/ssh/sshd_config' | xargs)/tcp
		systemctl start firewalld
		firewall-cmd --reload
	elif [ "${SYSTEM_OS}" == "DEBIAN" ]; then
		apt update -y
		apt install -y ca-certificates cron curl git lsof ufw
		curl -fsSL "https://deb.nodesource.com/setup_16.x" | bash
		apt install -y nodejs
		[ -e "/etc/ssh/sshd_config" ] && ufw allow $(awk -F 'Port ' '{print $2}' '/etc/ssh/sshd_config' | xargs)/tcp
		ufw enable <<-EOF
			y
		EOF
		ufw reload
	fi

	__info_msg "正在克隆 UnblockNeteaseMusic 服务端到本地。。。"
	mkdir -p "${UNM_SERV_BIN_DIR%/*}"
	git clone "${UNM_SERV_GIT_REPO}" "${UNM_SERV_BIN_DIR}" || { rm -rf "${UNM_SERV_BIN_DIR}"; __error_msg "克隆服务端失败。"; exit 1; }
	pushd "${UNM_SERV_BIN_DIR}"
	git config pull.ff only
	node "app.js" -h || { rm -rf "${UNM_SERV_BIN_DIR}"; __error_msg "服务端运行测试失败。"; exit 1; }
	popd

	[ -f "${UNM_SERV_ENV}" ] && {
		__info_msg "已在您的设备上找到 UnblockNeteaseMusic 服务端配置文件。"
		local UNM_SERV_USE_OLD_CONF
		read -rep "是否使用原配置文件 [Y/n]：" UNM_SERV_USE_OLD_CONF
		case "${UNM_SERV_USE_OLD_CONF}" in
		[nN][oO]|[nN])
			UNM_SERV_USE_OLD_CONF=""
			;;
		*)
			UNM_SERV_USE_OLD_CONF="true"
			source "${UNM_SERV_ENV}"
			UNM_SERV_LISTEN_PORT="$PORTS"
			;;
		esac
	}

	[ -z "${UNM_SERV_USE_OLD_CONF}" ] && {
		__info_msg "请设定服务端信息："
		local UNM_SERV_LISTEN_PORT UNM_SERV_LISTEN_PORT_DEFAULT
		UNM_SERV_LISTEN_PORT_DEFAULT="$(( RANDOM + 10000 ))"
		UNM_SERV_LISTEN_PORT_DEFAULT+=":$(( UNM_SERV_LISTEN_PORT_DEFAULT + 1 ))"
		read -rep "请输入监听端口（默认：${UNM_SERV_LISTEN_PORT_DEFAULT}）：" UNM_SERV_LISTEN_PORT
		[ -z "${UNM_SERV_LISTEN_PORT}" ] && UNM_SERV_LISTEN_PORT="${UNM_SERV_LISTEN_PORT_DEFAULT}"

		local UNM_SERV_USED_SOURCES
		read -rep "请输入欲使用的音源（默认：使用程序默认值）：" UNM_SERV_USED_SOURCES
		[ -n "${UNM_SERV_USED_SOURCES}" ] && UNM_SERV_USED_SOURCES="-o ${UNM_SERV_USED_SOURCES}"

		local UNM_SERV_USED_ENDPOINT UNM_SERV_USED_ENDPOINT_DEFAULT
		UNM_SERV_USED_ENDPOINT_DEFAULT="https://music.163.com"
		read -rep "请输入 EndPoint（默认：${UNM_SERV_USED_ENDPOINT_DEFAULT}）：" UNM_SERV_USED_ENDPOINT
		if [ "${UNM_SERV_USED_ENDPOINT}" == "-" ]; then
			UNM_SERV_USED_ENDPOINT=""
		else
			UNM_SERV_USED_ENDPOINT="-e ${UNM_SERV_USED_ENDPOINT:-$UNM_SERV_USED_ENDPOINT_DEFAULT}"
		fi

		local UNM_SERV_USED_HOST
		read -rep "请输入一个自定义网易云音乐服务器 IP（默认：不强制指定）：" UNM_SERV_USED_HOST
		[ -n "${UNM_SERV_USED_HOST}" ] && UNM_SERV_USED_HOST="-f ${UNM_SERV_USED_HOST}"

		local UNM_SERV_USED_PROXY
		read -rep "请输入 HTTP(S) 代理服务器地址（默认：不启用代理）：" UNM_SERV_USED_PROXY
		[ -n "${UNM_SERV_USED_PROXY}" ] && UNM_SERV_USED_PROXY="-u ${UNM_SERV_USED_PROXY}"

		local UNM_SERV_ENABLE_STRICT
		read -rep "是否启用严格模式 [Y/n]：" UNM_SERV_ENABLE_STRICT
		case "${UNM_SERV_ENABLE_STRICT}" in
			[nN][oO]|[nN]) UNM_SERV_ENABLE_STRICT="" ;;
			*) UNM_SERV_ENABLE_STRICT="-s" ;;
		esac

		local UNM_SERV_ENABLE_FLAC
		read -rep "是否启用无损音质获取 [Y/n]：" UNM_SERV_ENABLE_FLAC
		case "${UNM_SERV_ENABLE_FLAC}" in
			[nN][oO]|[nN]) UNM_SERV_ENABLE_FLAC="" ;;
			*) UNM_SERV_ENABLE_FLAC="true" ;;
		esac

		local UNM_SERV_ENABLE_LOCAL_VIP
		read -rep "是否启用本地黑胶伪装 [y/N]：" UNM_SERV_ENABLE_LOCAL_VIP
		case "${UNM_SERV_ENABLE_LOCAL_VIP}" in
			[yY][eE][sS]|[yY]) UNM_SERV_ENABLE_LOCAL_VIP="true" ;;
			*) UNM_SERV_ENABLE_LOCAL_VIP="" ;;
		esac

		__info_msg "正在保存配置文件。。。"
		mkdir -p "${UNM_SERV_CONF_DIR}"
		cat <<-EOF > "${UNM_SERV_ENV}"
			PORTS="${UNM_SERV_LISTEN_PORT}"
			SOURCES="${UNM_SERV_USED_SOURCES}"
			ENDPOINT="${UNM_SERV_USED_ENDPOINT}"
			HOST="${UNM_SERV_USED_HOST}"
			PROXY="${UNM_SERV_USED_PROXY}"
			STRICT="${UNM_SERV_ENABLE_STRICT}"
			ENABLE_FLAC="${UNM_SERV_ENABLE_FLAC}"
			ENABLE_LOCAL_VIP="${UNM_SERV_ENABLE_LOCAL_VIP}"
		EOF
	}

	__info_msg "正在设定防火墙规则。。。"
	setup_firewall add "${UNM_SERV_LISTEN_PORT}"

	__info_msg "正在配置自动更新。。。"
	local TEMP_CRONTAB_FILE="$(mktemp)"
	crontab -l > "${TEMP_CRONTAB_FILE}"
	echo -e "0 3 * * * { pushd \"${UNM_SERV_BIN_DIR}\"; git pull; popd; } > \"/dev/null\" 2>&1" >> "${TEMP_CRONTAB_FILE}"
	crontab "${TEMP_CRONTAB_FILE}"
	rm -f "${TEMP_CRONTAB_FILE}"

	__info_msg "正在配置 systemd 服务。。。"
	cat <<-EOF > "${UNM_SERV_SERVICE}"
		[Unit]
		Description=UnblockNeteaseMusic Server (Node.js version)
		After=network-online.target
		Wants=network-online.target systemd-networkd-wait-online.service

		[Service]
		User=root
		Group=root

		AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
		CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
		LimitNOFILE=1048576
		NoNewPrivileges=true

		EnvironmentFile=${UNM_SERV_ENV}

		WorkingDirectory=${UNM_SERV_BIN_DIR}
		ExecStart=/usr/bin/env node "${UNM_SERV_BIN_DIR}/app.js" -a 0.0.0.0 -p \$PORTS \$SOURCES \$ENDPOINT \$HOST \$PROXY \$STRICT
		Restart=always

		[Install]
		WantedBy=multi-user.target
	EOF
	systemctl enable "${UNM_SERV_SERVICE##*/}"

	touch "${UNM_SERV_BIN_DIR}/.install-done"
	
	start_stop_unm_server

	__info_msg "正在保存本脚本到 ${UNM_SERV_BIN}。。。"
	if curl -fsSL "${UNM_SERV_SCRIPT_URL}" -o "${UNM_SERV_BIN}"; then
		chmod 0755 "${UNM_SERV_BIN}"
	else
		rm -f "${UNM_SERV_BIN}"
		__error_msg "保存脚本失败。"
	fi

	__success_msg "UnblockNeteaseMusic 服务端安装完毕。"
	local UNM_SERV_IP="$(curl -fsSL "https://myip.ipip.net/s" || curl -fsSL "https://ipinfo.io/ip" || echo "127.0.0.1")"
	local UNM_SERV_ADDR="${GREEN_BACK}${UNM_SERV_IP}:${UNM_SERV_LISTEN_PORT}${DEFAULT_COLOR}"
	local UNM_SERV_PAC="${GREEN_BACK}http://${UNM_SERV_IP}:${UNM_SERV_LISTEN_PORT%:*}/proxy.pac${DEFAULT_COLOR}"
	__info_msg "UnblockNeteaseMusic 服务端监听地址：${UNM_SERV_ADDR}"
	__info_msg "UnblockNeteaseMusic 服务端自动代理文件地址：${UNM_SERV_PAC}"
	__info_msg "您可以输入 unm-server 以重新调起本脚本。"
}

function remove_unm_server(){
	[ ! -d "${UNM_SERV_BIN_DIR}" ] && {
		__error_msg "您目前尚未安装 UnblockNeteaseMusic 服务端。"
		exit 1
	}

	local COMFIRM_REMOVE
	__warning_msg "您即将移除 UnblockNeteaseMusic 服务端。"
		read -rep "请确认 [y/N]：" COMFIRM_REMOVE
		case "${COMFIRM_REMOVE}" in
		[yY][eE][sS]|[yY])
			__info_msg "正在停止运行 UnblockNeteaseMusic 服务端。。。"
			systemctl stop "${UNM_SERV_SERVICE##*/}"
			systemctl disable "${UNM_SERV_SERVICE##*/}"

			__info_msg "正在移除 UnblockNeteaseMusic 服务端相关文件。。。"
			rm -f "${UNM_SERV_SERVICE}"
			rm -f "${UNM_SERV_BIN}"
			rm -rf "${UNM_SERV_BIN_DIR}"

			__info_msg "正在移除防火墙规则。。。"
			source "$UNM_SERV_ENV"
			setup_firewall remove "$PORTS"

			__info_msg "正在移除自动更新。。。"
			local TEMP_CRONTAB_FILE="$(mktemp)"
			crontab -l > "${TEMP_CRONTAB_FILE}"
			sed -i "/${UNM_SERV_BIN_DIR//\//\\/}/d" "${TEMP_CRONTAB_FILE}"
			crontab "${TEMP_CRONTAB_FILE}"
			rm -f "${TEMP_CRONTAB_FILE}"

			local COMFIRM_REMOVE_CONFFILES
			__warning_msg "是否保留 UnblockNeteaseMusic 服务端配置文件？"
			read -rep "请确认 [Y/n]：" COMFIRM_REMOVE_CONFFILES
			case "${COMFIRM_REMOVE_CONFFILES}" in
				[nN][oO]|[nN]) __info_msg "正在移除配置文件。。。"; rm -rf "${UNM_SERV_CONF_DIR}" ;;
				*) __info_msg "配置文件已保留。"
				esac

			__success_msg "UnblockNeteaseMusic 服务端已从您的设备上移除。"
			;;
		*)
			__error_msg "操作已取消。"
			exit 2
			;;
		esac
}

function start_stop_unm_server(){
	[ ! -f "${UNM_SERV_BIN_DIR}/.install-done" ] && { __error_msg "您目前尚未安装 UnblockNeteaseMusic 服务端。"; exit 1; }

	if systemctl is-active "${UNM_SERV_SERVICE##*/}" > "/dev/null"; then
		__info_msg "正在停止 UnblockNeteaseMusic 服务端。。。"
		systemctl stop "${UNM_SERV_SERVICE##*/}"
		sleep 3s
		if [ "$(systemctl show --property MainPID --value ${UNM_SERV_SERVICE##*/})" -eq 0 ]; then
			__success_msg "UnblockNeteaseMusic 服务端已停止。"
		else
			__error_msg "无法停止 UnblockNeteaseMusic 服务端。"
			return 1
		fi
	else
		__info_msg "正在启动 UnblockNeteaseMusic 服务端。。。"
		systemctl start "${UNM_SERV_SERVICE##*/}"
		sleep 3s
		if systemctl is-active "${UNM_SERV_SERVICE##*/}" > "/dev/null" && [ "$(systemctl show --property MainPID --value ${UNM_SERV_SERVICE##*/})" -ne 0 ]; then
			__success_msg "UnblockNeteaseMusic 服务端已启动。"
		else
			__error_msg "无法启动 UnblockNeteaseMusic 服务端。"
			return 1
		fi
	fi
}

function restart_unm_server() {
	[ ! -f "${UNM_SERV_BIN_DIR}/.install-done" ] && { __error_msg "您目前尚未安装 UnblockNeteaseMusic 服务端。"; exit 1; }

	__info_msg "正在重启 UnblockNeteaseMusic 服务端。。。"
	systemctl restart "${UNM_SERV_SERVICE##*/}"
	sleep 3s
	if systemctl is-active "${UNM_SERV_SERVICE##*/}" > "/dev/null" && [ "$(systemctl show --property MainPID --value ${UNM_SERV_SERVICE##*/})" -ne 0 ]; then
		__success_msg "UnblockNeteaseMusic 服务端已重启。"
	else
		__error_msg "无法重启 UnblockNeteaseMusic 服务端。"
		return 1
	fi
}

function tweak_unm_server() {
	[ ! -f "${UNM_SERV_BIN_DIR}/.install-done" ] && { __error_msg "您目前尚未安装 UnblockNeteaseMusic 服务端。"; exit 1; }
	[ ! -f "${UNM_SERV_ENV}" ] && { __error_msg "UnblockNeteaseMusic 服务端配置文件已丢失，请重新安装。"; exit 1; }

	source "${UNM_SERV_ENV}"

	clear
	echo -e "更改 UnblockNeteaseMusic 服务端设定
----------------------------------------------
	0. 启用/禁用自动更新

	1. 更改监听端口
	2. 更改音源
	3. 更改 EndPoint
	4. 更改网易云音乐服务器 IP
	5. 更改代理设定
	6. 更改音源强制替换触发条件

	7. 启用/禁用严格模式
	8. 启用/禁用无损音质获取
	9. 启用/禁用本地黑胶伪装
	10. 启用/禁用缓存

	11. 设定 Joox Cookie
	12. 设定 Migu Cookie
	13. 设定 QQ Cookie
	14. 设定 Youtube API Key
	15. 设定自定义证书文件

	Enter. 退出设定
----------------------------------------------"
	local DO_ACTION
	read -rep "Action [0-15]: " DO_ACTION
	case "${DO_ACTION}" in
	"0")
		local UNM_SERV_AUTO_UPDATE UNM_SERV_AUTO_UPDATE_TIP
		if crontab -l | grep -q "${UNM_SERV_BIN_DIR}"; then
			UNM_SERV_AUTO_UPDATE_TIP="禁用"
		else
			UNM_SERV_AUTO_UPDATE_TIP="启用"
		fi

		read -rep "是否${UNM_SERV_AUTO_UPDATE_TIP}自动更新 [y/N]：" UNM_SERV_AUTO_UPDATE
		case "${UNM_SERV_AUTO_UPDATE}" in
		[yY][eE][sS]|[yY])
			local TEMP_CRONTAB_FILE="$(mktemp)"
			crontab -l > "${TEMP_CRONTAB_FILE}"
			if [ "${UNM_SERV_AUTO_UPDATE_TIP}" == "禁用" ]; then
				sed -i "/${UNM_SERV_BIN_DIR//\//\\/}/d" "${TEMP_CRONTAB_FILE}"
			else
				echo -e "0 3 * * * { pushd \"${UNM_SERV_BIN_DIR}\"; git pull; popd; } > \"/dev/null\" 2>&1" >> "${TEMP_CRONTAB_FILE}"
			fi
			crontab "${TEMP_CRONTAB_FILE}"
			rm -f "${TEMP_CRONTAB_FILE}"
			;;
		*)
			__info_msg "自动更新未改变。"
			return 2
			;;
		esac
		;;
	"1")
		local UNM_SERV_LISTEN_PORT
		read -rep "请输入监听端口（默认：${PORTS}）：" UNM_SERV_LISTEN_PORT
		if [ -z "${UNM_SERV_LISTEN_PORT}" ]; then
			__info_msg "端口未改变。"
		else
			sed -i "/PORTS=/d" "${UNM_SERV_ENV}"
			echo -e "PORTS=${UNM_SERV_LISTEN_PORT}" >> "${UNM_SERV_ENV}"
			__info_msg "正在设定防火墙。。。"
			setup_firewall remove "${PORTS}"
			setup_firewall add "${UNM_SERV_LISTEN_PORT}"
			__success_msg "端口已更改为 ${UNM_SERV_LISTEN_PORT}。"
		fi
		;;
	"2") tweak_unm_server_arg "请输入欲使用的音源（默认：${SOURCES#-o *}）：" "音源" "SOURCES" "-o " ;;
	"3") tweak_unm_server_arg "请输入欲使用的 EndPoint（默认：${ENDPOINT#-e *}）：" "EndPoint" "ENDPOINT" "-e " ;;
	"4") tweak_unm_server_arg "请输入一个自定义网易云音乐服务器 IP（默认：${HOST#-f *}）：" "网易云音乐服务器 IP" "HOST" "-f " ;;
	"5") tweak_unm_server_arg "请输入 HTTP(S) 代理服务器地址（默认：${PROXY#-u *}）" "代理服务器地址" "PROXY" "-u " ;;
	"6") tweak_unm_server_arg "请输入允许的最低源音质（默认：${MIN_BR}）：" "允许的最低源音质" "MIN_BR" ;;
	"7") tweak_unm_server_bool "STRICT" "严格模式" "-s" ;;
	"8") tweak_unm_server_bool "ENABLE_FLAC" "无损音质获取" ;;
	"9") tweak_unm_server_bool "ENABLE_LOCAL_VIP" "本地黑胶伪装" ;;
	"10") tweak_unm_server_bool "NO_CACHE" "【不使用缓存】" ;;
	"11") tweak_unm_server_arg "请输入 Joox Cookie（默认：${JOOX_COOKIE}）：" "Joox Cookie" "JOOX_COOKIE" ;;
	"12") tweak_unm_server_arg "请输入 Migu Cookie（默认：${MIGU_COOKIE}）：" "Migu Cookie" "MIGU_COOKIE" ;;
	"13") tweak_unm_server_arg "请输入 QQ Cookie（默认：${QQ_COOKIE}）：" "QQ Cookie" "QQ_COOKIE" ;;
	"14") tweak_unm_server_arg "请输入 Youtube API Key（默认：${YOUTUBE_KEY}）：" "Youtube API Key" "YOUTUBE_KEY" ;;
	"15")
		__info_msg "请将您的证书文件上传至 \"${UNM_SERV_CONF_DIR}\"。"
		local UNM_SERV_CUSTOM_CERT UNM_SERV_CUSTOM_CERT_KEY
		read -rep "请输入证书文件名（默认：${SIGN_CERT##*/}）：" UNM_SERV_CUSTOM_CERT
		read -rep "请输入密钥文件名（默认：${SIGN_KEY##*/}）：" UNM_SERV_CUSTOM_CERT_KEY
		if [ "${UNM_SERV_CUSTOM_CERT}" == "-" ] || [ "${UNM_SERV_CUSTOM_CERT_KEY}" == "-" ]; then
			sed -i "/SIGN_CERT=/d" "${UNM_SERV_READ_ARG}"
			sed -i "/SIGN_KEY=/d" "${UNM_SERV_READ_ARG}"
			restart_unm_server
			__success_msg "自定义证书文件设定已清空。"
		elif [ ! -e "${UNM_SERV_CONF_DIR}/${UNM_SERV_CUSTOM_CERT:-dummy.impossible.crt}" ] || [ ! -e "${UNM_SERV_CONF_DIR}/${UNM_SERV_CUSTOM_CERT_KEY:-dummy.impossible.key}" ]; then
			__warning_msg "证书文件不存在或未输入。"
		else
			sed -i "/SIGN_CERT=/d" "${UNM_SERV_READ_ARG}"
			sed -i "/SIGN_KEY=/d" "${UNM_SERV_READ_ARG}"
			echo -e "SIGN_CERT=\"${UNM_SERV_CONF_DIR}/${UNM_SERV_CUSTOM_CERT}\"" >> "${UNM_SERV_ENV}"
			echo -e "SIGN_KEY=\"${UNM_SERV_CONF_DIR}/${UNM_SERV_CUSTOM_CERT_KEY}\"" >> "${UNM_SERV_ENV}"
			restart_unm_server
			__success_msg "自定义证书文件已指定。"
		fi
		;;
	"")
		__info_msg "操作已取消。"
		exit 2
		;;
	*)
		__error_msg "未定义行为：${DO_ACTION}。"
		;;
	esac

	read -rep "按回车键继续。。。"
	tweak_unm_server
}

function tweak_unm_server_arg(){
	local UNM_SERV_READ_ARG
	read -rep "$1" UNM_SERV_READ_ARG
	if [ -z "${UNM_SERV_READ_ARG}" ]; then
		__info_msg "$2 未改变。"
		return 2
	elif [ "${UNM_SERV_READ_ARG}" == "-" ]; then
		sed -i "/$3=/d" "${UNM_SERV_ENV}"
		restart_unm_server
		__success_msg "$2 已清空。"
	else
		sed -i "/$3=/d" "${UNM_SERV_ENV}"
		echo -e "$3=\"$4${UNM_SERV_READ_ARG}\"" >> "${UNM_SERV_ENV}"
		restart_unm_server
		__success_msg "$2 已更改为 ${UNM_SERV_READ_ARG}。"
	fi
}

function tweak_unm_server_bool(){
	local UNM_SERV_READ_BOOL UNM_SERV_BOOL_TIP UNM_SERV_BOOL_MODIFY
	if [ "$(eval echo "\${$1}")" == "${3:-true}" ]; then
		UNM_SERV_BOOL_TIP="禁用"
	else
		UNM_SERV_BOOL_TIP="启用"
		UNM_SERV_BOOL_MODIFY=1
	fi
	read -rep "是否${UNM_SERV_BOOL_TIP}$2 [y/N]：" UNM_SERV_READ_BOOL
	case "${UNM_SERV_READ_BOOL}" in
	[yY][eE][sS]|[yY])
		sed -i "/$1=/d" "${UNM_SERV_ENV}"
		[ -n "${UNM_SERV_BOOL_MODIFY}" ] && echo -e "$1=\"${3:-true}\"" >> "${UNM_SERV_ENV}"
		restart_unm_server
		__info_msg "$2已${UNM_SERV_BOOL_TIP}。"
		;;
	*)
		__info_msg "$2未改变。"
		return 2
		;;
	esac
}

function update_unm_server() {
	[ ! -f "${UNM_SERV_BIN_DIR}/.install-done" ] && { __error_msg "您目前尚未安装 UnblockNeteaseMusic 服务端。"; exit 1; }

	__info_msg "正在更新 UnblockNeteaseMusic 服务端管理脚本。。。"
	local UNM_SERV_BIN_TEMP="$(mktemp)"
	if curl -fsSL "${UNM_SERV_SCRIPT_URL}" -o "${UNM_SERV_BIN_TEMP}"; then
		mv -f "${UNM_SERV_BIN_TEMP}" "${UNM_SERV_BIN}"
		chmod 0755 "${UNM_SERV_BIN}"
		__success_msg "UnblockNeteaseMusic 服务端管理脚本更新成功。"
	else
		rm -f "${UNM_SERV_BIN_TEMP}"
		__error_msg "UnblockNeteaseMusic 服务端管理脚本更新失败。"
	fi

	__info_msg "正在更新 UnblockNeteaseMusic 服务端。。。"
	pushd "${UNM_SERV_BIN_DIR}"
	if git pull; then
		__success_msg "Pull 最新 commits 成功。"
		restart_unm_server
	else
		__error_msg "Pull 最新 commits 失败。"
		exit 1
	fi
}

function setup_firewall() {
	local PORT_HTTP="${2%:*}"
	local PORT_HTTPS="${2#:*}"
	if [ "${SYSTEM_OS}" == "RHEL" ]; then
		firewall-cmd --permanent --zone=public --$1-port="${PORT_HTTP}/tcp"
		[ "${PORT_HTTPS}" != "${PORT_HTTP}" ] && firewall-cmd --permanent --zone=public --$1-port="${PORT_HTTPS}/tcp"
		firewall-cmd --reload
	elif [ "${SYSTEM_OS}" == "DEBIAN" ]; then
		local UFW_ARG
		[ "$1" == "remove" ] && UFW_ARG="delete"
		ufw $UFW_ARG allow "${PORT_HTTP}/tcp"
		[ "${PORT_HTTPS}" != "${PORT_HTTP}" ] && ufw $UFW_ARG allow "${PORT_HTTPS}/tcp"
		ufw reload
	fi
}

function main() {
	base_check
	print_menu
}

main

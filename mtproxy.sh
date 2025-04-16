#!/bin/bash

Red="\033[31m" # 红色
Green="\033[32m" # 绿色
Yellow="\033[33m" # 黄色
Blue="\033[34m" # 蓝色
Nc="\033[0m" # 重置颜色
Red_globa="\033[41;37m" # 红底白字
Green_globa="\033[42;37m" # 绿底白字
Yellow_globa="\033[43;37m" # 黄底白字
Blue_globa="\033[44;37m" # 蓝底白字
Info="${Green}[信息]${Nc}"
Error="${Red}[错误]${Nc}"
Tip="${Yellow}[提示]${Nc}"

mtp_dir="/var/mtproxy"
mtp_file="${mtp_dir}/mtproxy.py"
mtp_conf="${mtp_dir}/config.json"
mtp_info="${mtp_dir}/mtp_info"
mtp_log="${mtp_dir}/log_mtproxy.log"


# 检查是否为root用户
check_root(){
    if [ "$(id -u)" != "0" ]; then
        echo -e "${Error} 当前非ROOT账号(或没有ROOT权限)，无法继续操作，请更换ROOT账号或使用 ${Green_globa}sudo -i${Nc} 命令获取临时ROOT权限（执行后可能会提示输入当前账号的密码）。"
        exit 1
    fi
}

check_release(){
    if [[ -e /etc/os-release ]]; then
        . /etc/os-release
        release=$ID
    elif [[ -e /usr/lib/os-release ]]; then
        . /usr/lib/os-release
        release=$ID
    fi
    os_version=$(echo $VERSION_ID | cut -d. -f1,2)

    if [[ "${release}" == "ol" ]]; then
        release=oracle
        os_version=${os_version%.*}
        if [[ ${os_version} -lt 8 ]]; then
            echo -e "${Info} 你的系统是${Red} $release $os_version ${Nc}"
            echo -e "${Error} 请使用${Red} $release 8${Nc} 或更高版本" && exit 1
        fi
    elif [[ "${release}" == "centos" ]]; then
        if [[ ${os_version} -lt 8 ]]; then
            echo -e "${Info} 你的系统是${Red} $release $os_version ${Nc}"
            echo -e "${Error} 请使用${Red} $release 8${Nc} 或更高版本" && exit 1
        fi
    elif [[ "${release}" == "fedora" ]]; then
        if [[ ${os_version} -lt 25 ]]; then
            echo -e "${Info} 你的系统是${Red} $release $os_version ${Nc}"
            echo -e "${Error} 请使用${Red} $release 25${Nc} 或更高版本" && exit 1
        fi
    elif [[ ! "${release}" =~ ^(kali|ubuntu|debian|almalinux|rocky|alpine)$ ]]; then
        echo -e "${Error} 抱歉，此脚本不支持您的操作系统。"
        echo -e "${Info} 请确保您使用的是以下支持的操作系统之一："
        echo -e "-${Red} Ubuntu${Nc} "
        echo -e "-${Red} Debian ${Nc}"
        echo -e "-${Red} CentOS 8+${Nc}"
        echo -e "-${Red} Fedora 25+${Nc}"
        echo -e "-${Red} Kali ${Nc}"
        echo -e "-${Red} AlmaLinux ${Nc}"
        echo -e "-${Red} Rocky Linux ${Nc}"
        echo -e "-${Red} Oracle Linux 8+${Nc}"
        echo -e "-${Red} Alpine Linux${Nc}"
        exit 1
    fi
}

check_pmc(){
    check_release
    if [[ "$release" == "debian" || "$release" == "ubuntu" || "$release" == "kali" ]]; then
        updates="apt update -y"
        installs="apt install -y"
        check_install="dpkg -s"
        apps=("openssl" "python3" "python3-cryptography" "xxd" "procps" "net-tools")
    elif [[ "$release" == "alpine" ]]; then
        updates="apk update -f"
        installs="apk add -f"
        check_install="apk info -e"
        apps=("openssl" "python3" "py3-cryptography" "xxd" "procps" "net-tools")
    elif [[ "$release" == "almalinux" || "$release" == "rocky" || "$release" == "oracle" ]]; then
        updates="dnf update -y"
        installs="dnf install -y"
        check_install="dnf list installed"
        apps=("openssl" "python3.11" "python3.11-cryptography" "vim-common" "procps-ng" "net-tools")
    elif [[ "$release" == "centos" ]]; then
        updates="yum update -y"
        installs="yum install -y"
        check_install="yum list installed"
        apps=("openssl" "python3" "python3-cryptography" "vim-common" "procps-ng" "net-tools")
    elif [[ "$release" == "fedora" ]]; then
        updates="dnf update -y"
        installs="dnf install -y"
        check_install="dnf list installed"
        apps=("openssl" "python3" "python3-cryptography" "vim-common" "procps-ng" "net-tools")
    fi
}

install_base(){
    check_pmc
    cmds=("openssl" "python3" "cryptography" "xxd" "ps" "netstat")
    echo -e "${Info} 你的系统是${Red} $release $os_version ${Nc}"
    echo
    for g in "${!apps[@]}"; do
        if ! $check_install "${apps[$g]}" &> /dev/null; then
            CMDS+=(${cmds[g]})
            DEPS+=("${apps[$g]}")
        fi
    done
    
    if [ ${#DEPS[@]} -gt 0 ]; then
        echo -e "${Tip} 安装依赖列表：${Green}${CMDS[@]}${Nc} 请稍后..."
        $updates &> /dev/null
        $installs "${DEPS[@]}" &> /dev/null
    else
        echo -e "${Info} 所有依赖已存在，不需要额外安装。"
    fi

    if [[ "$release" == "almalinux" || "$release" == "rocky" || "$release" == "oracle" ]]; then
        ln -sf /usr/bin/python3.11 /usr/bin/python3
    fi
}

check_pid(){
    PID=$(ps -ef | grep "mtproxy.py" | grep -v "grep" | awk '{print $2}')
}

# 检查是否安装MTProxy
check_installed_status(){
    if [[ ! -e "${mtp_file}" ]]; then
        echo -e "${Error} MTProxy 没有安装，请检查 !"
        exit 1
    fi
}

Download(){
    if [[ ! -e "${mtp_dir}" ]]; then
        mkdir "${mtp_dir}"
    fi
    get_public_ip
    cd "${mtp_dir}"
    echo -e "${Info} 开始下载/安装..."
    curl -sO https://raw.githubusercontent.com/jyucoeng/mtproxy/main/mtproxy.py

    cat >${mtp_conf} <<-EOF
PORT = 443

# 密匙 -> secret（32 个十六进制字符）
USERS = {
    "user": "0123456789abcdef0123456789abcdef",
}

MODES = {
    # 经典模式，易于检测
    "classic": False,

    # 使代理服务器更难检测
    # 可能与非常老的客户端不兼容
    "secure": False,

    # 使代理更难被发现
    # 可能与旧客户端不兼容
    "tls": True
}

# TLS 模式的域，不良客户端在此被代理
# 使用随机的现有域，代理会在启动时检查它
# TLS_DOMAIN = "www.google.com"

# 用于广告的标签，可从 @MTProxybot 获取
# AD_TAG = ""
EOF

cat >${mtp_info} <<-EOF
IPv4=$IPv4
IPv6=$IPv6
PORT=443
SECURE=ee65ae12e414c319fb6aeef9924290825a6974756e65732e6170706c652e636f6d
TAG=
EOF
}

Write_Service(){
    echo -e "${Info} 开始写入 Service..."
    check_release
    if [[ "$release" == "alpine" ]]; then
        cat >/etc/init.d/mtproxy <<-'EOF'
#!/sbin/openrc-run

name="mtproxy"
description="mtproxy service"
command="/bin/sh"
command_args="-c 'python3 /var/mtproxy/mtproxy.py --config /var/mtproxy/config.json > /var/mtproxy/log_mtproxy.log'"
command_background="yes"
pidfile="/var/run/${RC_SVCNAME}.pid"
start_stop_daemon_args="--user root:root"
EOF
chmod +x /etc/init.d/mtproxy
rc-update add mtproxy default
else
    cat >/lib/systemd/system/mtproxy.service <<-'EOF'
[Unit]
Description=MTProxy
After=network.target

[Service]
User=root
Group=root
WorkingDirectory=/var/mtproxy
ExecStart=python3 /var/mtproxy/mtproxy.py --config /var/mtproxy/config.json
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
systemctl enable mtproxy
    fi
}

Read_config(){
    IPv4=$(cat ${mtp_info} | grep 'IPv4=' | cut -d'=' -f2 | grep -P '[.]')
    IPv6=$(cat ${mtp_info} | grep 'IPv6=' | cut -d'=' -f2 | grep -P '[:]')
    PORT=$(cat ${mtp_info} | grep 'PORT=' | cut -d'=' -f2)
    SECURE=$(cat ${mtp_info} | grep 'SECURE=' | cut -d'=' -f2)
    TAG=$(cat ${mtp_info} | grep 'TAG=' | cut -d'=' -f2)
}

Set_port(){
    while true; do
        echo -e "${Tip} 请输入 MTProxy 端口 [443-65535]"
        read -e -p "(默认：随机生成):" mtp_port
        [[ -z "${mtp_port}" ]] && mtp_port=$(shuf -i443-65000 -n1)
        if [[ ${mtp_port} -ge 443 ]] && [[ ${mtp_port} -le 65535 ]]; then
            echo && echo "========================"
            echo -e "  端口 : ${Red_globa} ${mtp_port} ${Nc}"
            echo "========================" && echo
            break
        else
            echo "输入错误, 请输入正确的端口。"
        fi
    done
    sed -i "s/^#\?PORT.*/PORT = $mtp_port/g" $mtp_conf
    sed -i "s/^#\?PORT.*/PORT=$mtp_port/g" $mtp_info
}

Set_passwd(){
    echo -e "${Tip} 请输入 MTProxy 密匙（普通密钥必须为32个十六进制字符，可在网站 https://www.lzltool.com/Tools/RandomHex 生成，建议留空随机生成）"
    read -e -p "(默认：随机生成):" mtp_passwd
    if [[ -z "${mtp_passwd}" ]]; then
        mtp_passwd=$(openssl rand -hex 16)
    fi
    sed -i 's/^#\?.*user".*/    "user": "'"$mtp_passwd"'",/g' $mtp_conf

    read -e -p "(是否开启TLS伪装？[Y/n]):" mtp_tls
    [[ -z "${mtp_tls}" ]] && mtp_tls="Y"
    if [[ "${mtp_tls}" == [Yy] ]]; then
        echo -e "${Tip} 请输入TLS伪装域名 $Red(无法使用被墙的域名。)$Nc"
        read -e -p "(默认：itunes.apple.com):" fake_domain
        [[ -z "${fake_domain}" ]] && fake_domain="itunes.apple.com"
        sed -i 's/^#\?.*secure.*/    "secure": False,/g' $mtp_conf
        sed -i 's/^#\?.*tls.*/    "tls": True/g' $mtp_conf
        sed -i 's/^#\?.*TLS_DOMAIN.*/TLS_DOMAIN = "'"$fake_domain"'"/g' $mtp_conf
        mtp_secure="ee${mtp_passwd}$(echo -n $fake_domain | xxd -ps -c 200)"
        sed -i "s/^#\?SECURE.*/SECURE=$mtp_secure/g" $mtp_info
        echo && echo "========================"
        echo -e "  密匙 : ${Red_globa} ${mtp_secure} ${Nc}"
        echo "========================" && echo
    else
        sed -i 's/^#\?.*secure.*/    "secure": True,/g' $mtp_conf
        sed -i 's/^#\?.*tls.*/    "tls": False/g' $mtp_conf
        mtp_secure="dd${mtp_passwd}"
        sed -i "s/^#\?SECURE.*/SECURE=$mtp_secure/g" $mtp_info
        echo && echo "========================"
        echo -e "  密匙 : ${Red_globa} ${mtp_secure} ${Nc}"
        echo "========================" && echo
    fi
}

Set_tag(){
    echo -e "${Tip} 请输入 MTProxy 的 TAG标签（TAG标签必须是32位，TAG标签只有在通过官方机器人 @MTProxybot 分享代理账号后才会获得，不清楚请留空回车）"
    read -e -p "(默认：回车跳过):" mtp_tag
    if [[ ! -z "${mtp_tag}" ]]; then
        echo && echo "========================"
        echo -e "  TAG : ${Red_globa} ${mtp_tag} ${Nc}"
        echo "========================"
        sed -i 's/^#\?.*AD_TAG.*/AD_TAG = "'"$mtp_tag"'"/g' $mtp_conf
        sed -i "s/^#\?TAG.*/TAG=$mtp_tag/g" $mtp_info
    else
        sed -i 's/^#\?.*AD_TAG.*/# AD_TAG = ""/g' $mtp_conf
        sed -i "s/^#\?TAG.*/TAG=$mtp_tag/g" $mtp_info
    fi
}

Set(){
    echo -e "${Info} 开始设置 用户配置..."
    check_installed_status
    echo && echo -e "你要做什么？
${Green} 1.${Nc}  修改 端口配置
${Green} 2.${Nc}  修改 密码配置
${Green} 3.${Nc}  修改 TAG 配置
${Green} 4.${Nc}  修改 全部配置" && echo
    read -e -p "(默认: 取消):" mtp_modify
    [[ -z "${mtp_modify}" ]] && echo -e "${Info} 已取消..." && exit 1
    if [[ "${mtp_modify}" == "1" ]]; then
        Set_port
        Restart
    elif [[ "${mtp_modify}" == "2" ]]; then
        Set_passwd
        Restart
    elif [[ "${mtp_modify}" == "3" ]]; then
        Set_tag
        Restart
    elif [[ "${mtp_modify}" == "4" ]]; then
        Set_port
        Set_passwd
        Set_tag
        Restart
    else
        echo -e "${Error} 请输入正确的数字(1-4)" && exit 1
    fi
}

Install(){
    [[ -e ${mtp_file} ]] && echo -e "${Error} 检测到 MTProxy 已安装 !" && exit 1
    install_base
    Download
    Set_port
    Set_passwd
    Set_tag
    Write_Service
    echo -e "${Info} 所有步骤 执行完毕，开始启动..."
    Start
}

start_mtproxy(){
    check_release
    if [[ "$release" == "alpine" ]]; then
        rc-service mtproxy start >/dev/null 2>&1
    else
        systemctl start mtproxy.service >/dev/null 2>&1
    fi
}

stop_mtproxy(){
    check_release
    if [[ "$release" == "alpine" ]]; then
        rc-service mtproxy stop >/dev/null 2>&1
    else
        systemctl stop mtproxy.service >/dev/null 2>&1
    fi
}

Start(){
    check_installed_status
    check_pid
    if [[ ! -z ${PID} ]]; then
        echo -e "${Error} MTProxy 正在运行，请检查 !"
        sleep 1s
        menu
    else
        start_mtproxy
        sleep 1s
        check_pid
        if [[ ! -z ${PID} ]]; then
            View
        fi
    fi
}

Stop(){
    check_installed_status
    check_pid
    if [[ -z ${PID} ]]; then
        echo -e "${Error} MTProxy 没有运行，请检查 !"
        sleep 1s
        menu
    else
        stop_mtproxy
        sleep 1s
        menu
    fi
}

Restart(){
    check_installed_status
    check_pid
    if [[ ! -z ${PID} ]]; then
        stop_mtproxy
        sleep 1s
    fi
    start_mtproxy
    sleep 1s
    check_pid
    [[ ! -z ${PID} ]] && View
}

Uninstall(){
    check_installed_status
    echo -e "${Tip} 确定要卸载 MTProxy ? (y/N)"
    echo
    read -e -p "(默认: n):" unyn
    [[ -z ${unyn} ]] && unyn="n"
    if [[ ${unyn} == [Yy] ]]; then
        check_pid
        if [[ ! -z $PID ]]; then
            stop_mtproxy
        fi

        check_release
        if [[ "$release" == "alpine" ]]; then
            rc-update del mtproxy default >/dev/null 2>&1
        else
            systemctl disable mtproxy.service >/dev/null 2>&1
        fi
        rm -rf ${mtp_dir}  /lib/systemd/system/mtproxy.service /etc/init.d/mtproxy
        echo -e "${Info} MTProxy 卸载完成 !"
        echo
    else
        echo
        echo -e "${Tip} 卸载已取消..."
        echo
    fi
}
get_public_ip(){
    InFaces=($(ls /sys/class/net | grep -E '^(eth|ens|eno|esp|enp|venet|veth|vif)'))
    IP_API=(
        "api64.ipify.org"
        "ip.sb"
        "ifconfig.me"
        "icanhazip.com"
    )

    for iface in "${InFaces[@]}"; do
        for ip_api in "${IP_API[@]}"; do
            IPv4=$(curl -s4 --max-time 2 --interface "$iface" "$ip_api")
            IPv6=$(curl -s6 --max-time 2 --interface "$iface" "$ip_api")

            if [[ -n "$IPv4" || -n "$IPv6" ]]; then # 检查是否获取到IP地址
                break 2 # 获取到任一IP类型停止循环
            fi
        done
    done
}

View(){
    check_installed_status
    Read_config
    clear && echo
    echo -e "Mtproto Proxy 用户配置："
    echo -e "————————————————"
    echo -e " 地址\t: ${Green}${IPv4}${Nc}"
    [[ ! -z "${IPv6}" ]] && echo -e " 地址\t: ${Green}${IPv6}${Nc}"
    echo -e " 端口\t: ${Green}${PORT}${Nc}"
    echo -e " 密匙\t: ${Green}${SECURE}${Nc}"
    [[ ! -z "${TAG}" ]] && echo -e " TAG \t: ${Green}${TAG}${Nc}"
    echo -e " IPv4 tg代理链接\t: ${Red}https://t.me/proxy?server=${IPv4}&port=${PORT}&secret=${SECURE}${Nc}"
    echo -e " IPv4 tg代理链接\t: ${Red}tg://proxy?server=${IPv4}&port=${PORT}&secret=${SECURE}${Nc}"
    [[ ! -z "${IPv6}" ]] && echo -e " IPv6 tg代理链接\t: ${Red}tg://proxy?server=${IPv6}&port=${PORT}&secret=${SECURE}${Nc}"
    [[ ! -z "${IPv6}" ]] && echo -e " IPv6 tg代理链接\t: ${Red}https://t.me/proxy?server=${IPv6}&port=${PORT}&secret=${SECURE}${Nc}"
    echo
    echo -e "${Tip} 密匙头部的 ${Green}ee${Nc} 字符是代表客户端启用 ${Green}TLS伪装模式${Nc} ，可以降低服务器被墙几率。"
    echo -e "${Tip} 密匙头部的 ${Green}dd${Nc} 字符是代表客户端启用 ${Green}安全混淆模式${Nc}（TLS伪装模式除外），可以降低服务器被墙几率。"
    backmenu
}

View_Log(){
    check_installed_status
    check_release
    echo && echo -e "${Tip} 按 ${Red}Ctrl+C${Nc} 终止查看日志。"
    if [[ "$release" == "alpine" ]]; then
        tail -f /var/mtproxy/log_mtproxy.log
    else
        journalctl -u mtproxy -f
    fi
}

Esc_Shell(){
    exit 0
}

backmenu(){
    echo ""
    read -rp "请输入“y”退出, 或按任意键回到主菜单：" backmenuInput
    case "$backmenuInput" in
        y) exit 1 ;;
        *) menu ;;
    esac
}

menu(){
    clear
    echo -e "${Green}######################################
#          ${Red}MTProxy python版一键脚本          ${Green}#
#         作者: ${Yellow}Little Doraemon  ${Green}#
######################################

 0.${Nc} 退出脚本
———————————————————————
${Green} 1.${Nc} 安装 MTProxy
${Green} 2.${Nc} 卸载 MTProxy
———————————————————————
${Green} 3.${Nc} 启动 MTProxy
${Green} 4.${Nc} 停止 MTProxy
${Green} 5.${Nc} 重启 MTProxy
———————————————————————
${Green} 6.${Nc} 设置 MTProxy配置
${Green} 7.${Nc} 查看 MTProxy链接
${Green} 8.${Nc} 查看 MTProxy日志
———————————————————————" && echo

    if [[ -e ${mtp_file} ]]; then
        check_pid
        if [[ ! -z "${PID}" ]]; then
            echo -e " 当前状态: ${Green}已安装${Nc} 并 ${Green}已启动${Nc}"
            check_installed_status
            Read_config
            echo -e "${Info} IPv4 链接: ${Red}https://t.me/proxy?server=${IPv4}&port=${PORT}&secret=${SECURE}${Nc}"
            [[ ! -z "${IPv6}" ]] && echo -e "${Info} IPv6 链接: ${Red}https://t.me/proxy?server=${IPv6}&port=${PORT}&secret=${SECURE}${Nc}"
        else
            echo -e " 当前状态: ${Green}已安装${Nc} 但 ${Red}未启动${Nc}"
        fi
    else
        echo -e " 当前状态: ${Red}未安装${Nc}"
    fi
    echo
    read -e -p " 请输入数字 [0-8]:" num
    case "$num" in
        0)
            Esc_Shell
            ;;
        1)
            Install
            ;;
        2)
            Uninstall
            ;;
        3)
            Start
            ;;
        4)
            Stop
            ;;
        5)
            Restart
            ;;
        6)
            Set
            ;;
        7)
            View
            ;;
        8)
            View_Log
            ;;
        *)
            echo -e "${Error} 请输入正确数字 [0-8]"
            ;;
    esac
}

check_root
menu

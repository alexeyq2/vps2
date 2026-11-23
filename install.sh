set -e  # остановиться при ошибке

GREEN=$(tput setaf 2) # Set foreground color to red
NC=$(tput sgr0)    # Reset all attributes

cat << EOF 
$GREEN

      VPS со своим HTTPS-сайтом для VLESS
            (steal-from-yourself)

* получение и авто-продление HTTPS сертификата oт Let's Encrypt
* файлообменник с веб-мордой
* URL подписки для программ-клиентов (subscription URL)

Подготовка машины:
* Установка git, docker, утилит, настройка сети
* Скачивание кода проекта
$NC
EOF


if ! sudo --version >/dev/null; then
    [ $EUID != 0 ] && echo "Не установлен sudo и не root доступ, установка невозможна" && exit 1 
    # мы - root без sudo
    # все равно поставим sudo, далее скрипт должен его использовать - он может быть запущен и не от root

    echo "Устанавливаем sudo..."
    apt update
    apt install -yq sudo
else
    sudo apt -q update
fi

sudo apt install -yq git-core curl htop mc nano apt-transport-https ca-certificates

## Логи
# уменьшить размер системных логов - логи докера могут разрастись до гигабайт в /var/log/journal
grep "SystemMaxUse=100M" /etc/systemd/journald.conf >/dev/null \
|| echo "SystemMaxUse=100M" | sudo tee -a /etc/systemd/journald.conf

sudo systemctl restart systemd-journald
echo Syslog настроен OK

## BBR

CHANGED=false

add_if_missing() {
    grep -q "^[[:space:]]*$1[[:space:]]*=" "/etc/sysctl.conf" 2>/dev/null || {
        echo "$1" | sudo tee -a "/etc/sysctl.conf"
        return 0
    }
    return 1
}

add_if_missing "net.core.default_qdisc=fq" && CHANGED=true
add_if_missing "net.ipv4.tcp_congestion_control=bbr" && CHANGED=true

$CHANGED && sudo sysctl -p >/dev/null 2>&1

echo $GREEN Текущие настройки TCP:
sudo sysctl net.ipv4.tcp_congestion_control net.core.default_qdisc
echo $NC


## DOCKER COMPOSE v2

if docker compose --version &> /dev/null ;then
    echo "$GREEN Docket compose уже установлен, OK $NC"
    DOCKER_WARNING=
else
    DOCKER_WARNING="Установлен docker. Выполните команду newgrp docker или перелогинитьтесь"
    
    # Add Docker's official GPG key:
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    # Add the repository to Apt sources:
    sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF

    sudo apt update
    sudo apt -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    sudo systemctl enable docker
    sudo systemctl start docker

    CURRENT_USER=${SUDO_USER:-$(whoami)}
    sudo usermod -aG docker $CURRENT_USER
fi

# Память - нужен свап, иначе может не хватать памяти при долгом аптайм
add_if_missing "vm.swappiness=10"

[ -f /swapfile ] && sudo swapoff /swapfile || true
sudo rm -rf /swapfile

sudo fallocate -l 500M /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
if ! grep -q swapfile /etc/fstab; then
    echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
fi

#!/bin/bash
#v2.0
clear

# Função para exibir informações do sistema
show_system_info() {
    echo "-------- Informações do Sistema --------"
    echo "Carga da CPU:"
    uptime
    echo "--------------------------------------"
    echo "Uso de Memória e Swap:"
    free -m
    echo "--------------------------------------"
}

# Exibir informações antes da execução
show_system_info

apt update
apt install curl -y
sleep 1

clear


show_menu() {
  echo "Deseja receber informações da instalação via Telegram? (s/n)"
  read -r choice
  case "$choice" in
    s|S) setup_telegram_notifications ;;
    *) ;;
  esac
}

setup_telegram_notifications() {
  echo "Por favor, insira o BOT_TOKEN do seu bot do Telegram:"
  read -r TELEGRAM_BOT_TOKEN

  echo "Agora, insira o CHAT_ID do seu chat no Telegram:"
  read -r TELEGRAM_CHAT_ID
}

send_telegram_message() {
  local message="$1"
  message="${message//$'\n'/%0A}"
  message="${message//$'\r'/}"  # Remover caracteres de retorno de carro
  curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
  -d "chat_id=$TELEGRAM_CHAT_ID" -d "text=$message" -d "parse_mode=HTML"
}

clear

show_menu

if [[ -n $TELEGRAM_BOT_TOKEN && -n $TELEGRAM_CHAT_ID ]]; then
  # Envia mensagem de início
  send_telegram_message "Olá, a instalação do seu servidor Zabbix foi iniciada.
Pode buscar um café, uma água ou uma cerveja, eu te aviso quando precisar de interação."

  # Função para obter o IP externo usando um serviço de terceiros
  get_external_ip() {
    curl -s ifconfig.me
  }

  # Coleta de informações do sistema
  OS=$(lsb_release -d | cut -f2)  # Obtém o sistema operacional
  MEMORY=$(free -m | awk '/Mem:/ {print $2 "MB"}')  # Obtém a memória RAM
  DISK=$(df -h / | awk 'NR==2 {print $2}')  # Obtém o tamanho do disco
  LOCAL_IP=$(hostname -I | awk '{print $1}')  # Obtém o IP local
  EXTERNAL_IP=$(get_external_ip)  # Obtém o IP externo

  # Mensagem a ser enviada via Telegram com as informações coletadas
  MESSAGE="Sistema: $OS
Memória RAM: $MEMORY
Disco: $DISK
IP Local: $LOCAL_IP
IP Externo: $EXTERNAL_IP"

  #send_telegram_message "Olá, a instalação do seu servidor Zabbix foi iniciada.
#Pode buscar um café, uma água ou uma cerveja, eu te aviso quando precisar de interação."

  # Envia a mensagem via Telegram
  send_telegram_message "$MESSAGE"

  # Verifica se o usuário é root
  if [ "$EUID" -ne 0 ]; then
    send_telegram_message "Por favor, execute como root ou utilizando sudo."
    exit 1
  fi

  # Verifica se o servidor LAMP está instalado e instala se não estiver
  if ! dpkg -l | grep -q "^ii.*apache2" || ! dpkg -l | grep -q "^ii.*mysql-server" || ! dpkg -l | grep -q "^ii.*php"; then
    send_telegram_message "Iniciando instalação do servidor LAMP..."
    apt install lamp-server^ -y || {
      send_telegram_message "Erro ao instalar o servidor LAMP. Verifique e tente novamente."
      exit 1
    }
  else
    send_telegram_message "Servidor LAMP instalado, continuando..."
    clear
  fi

  # Adiciona o repositório do Zabbix
  send_telegram_message "Adicionando o repositório do Zabbix..."
  wget https://repo.zabbix.com/zabbix/6.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_6.0-4+ubuntu22.04_all.deb
  #-O /tmp/zabbix-release.deb
  dpkg -i zabbix-release_6.0-4+ubuntu22.04_all.deb
  
  send_telegram_message "Atualizando lista de pacotes..."
  apt update
  clear
  # Instalação do Zabbix Server, Frontend e Agent
  send_telegram_message "Instalando o Zabbix Server, Frontend e Agent..."
  apt install zabbix-server-mysql zabbix-frontend-php zabbix-apache-conf zabbix-sql-scripts zabbix-agent -y || {
    send_telegram_message "Erro ao instalar o Zabbix Server. Verifique e tente novamente."
    exit 1
  }
  clear
  sleep 2

  send_telegram_message "Vai lá digitar a senha que será utilizada no banco de dados"
  clear 

  # Configuração do banco de dados MySQL para o Zabbix
 read -s -p "Digite a senha para o usuário 'zabbix' no MySQL: " MYSQL_PASSWORD

mysql_command="mysql -uroot -p$MYSQL_PASSWORD"

$mysql_command <<EOF
    create database zabbix character set utf8mb4 collate utf8mb4_bin;
    create user 'zabbix'@'localhost' identified by '$MYSQL_PASSWORD';
    grant all privileges on zabbix.* to 'zabbix'@'localhost';
    set global log_bin_trust_function_creators = 1;
    quit
EOF

sleep 5
clear

send_telegram_message "Agora dependendo do seu server pode demorar até copiar as tabelas, vai tomar o que vc pegou."
clear

zcat /usr/share/zabbix-sql-scripts/mysql/server.sql.gz | $mysql_command zabbix 

sed -i "s/# DBPassword=/DBPassword=$MYSQL_PASSWORD/" /etc/zabbix/zabbix_server.conf

$mysql_command <<EOF
    set global log_bin_trust_function_creators = 0;
    quit
EOF

git clone https://github.com/limatecnologia/zabbix.git
cd zabbix/
cd img/
mv sermais.png /usr/share/zabbix/assets/img
cd ..
mv brand.conf.php /usr/share/zabbix/local/conf


  # Reinicia os serviços
  send_telegram_message "Reiniciando os serviços..."
  systemctl restart zabbix-server zabbix-agent apache2 mysql || {
    send_telegram_message "Erro ao reiniciar os serviços. Verifique e tente novamente."
    exit 1
  }

  # Habilita os serviços para iniciar com o sistema
  send_telegram_message "Habilitando os serviços para iniciar com o sistema..."
  systemctl enable zabbix-server zabbix-agent apache2 mysql || {
    send_telegram_message "Erro ao habilitar os serviços. Verifique e tente novamente."
    exit 1
  }

  sleep 1
  clear

  sed -i 's|DocumentRoot /var/www/html|DocumentRoot /usr/share/zabbix|g' /etc/apache2/sites-enabled/000-default.conf
  systemctl restart apache2.service
  clear
  
  send_telegram_message "A instalação do Zabbix Server foi concluída."
  send_telegram_message "Acesse no seu navegador http://$LOCAL_IP para finalizar a instalação."

  clear

  # Exibir informações após a execução
  echo "A instalação do Zabbix Server foi concluída."
  echo "Acesse no seu navegador http://$LOCAL_IP para finalizar a instalação."
  show_system_info
else
  echo "Continuando a instalação sem notificações via Telegram."
fi

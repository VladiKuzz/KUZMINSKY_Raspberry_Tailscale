#!/bin/bash

############################################################
# Script di installazione automatica
# Laboratorio Raspberry Pi + Tailscale
# 
# Installa: Apache, PHP, MySQL, Tailscale, Firewall
# Clona: https://github.com/federicomaniglio/Webapp_Laboratorio_Raspberry
# Requisiti: Debian/Ubuntu/Raspberry Pi OS
# Esecuzione: sudo bash install.sh
############################################################

set -e  # Esce in caso di errore

# Colori per output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[i]${NC} $1"
}

# Banner
echo ""
echo "=============================================="
echo "  LABORATORIO RASPBERRY PI + TAILSCALE"
echo "  Stack LAMP + Auto-setup Database"
echo "=============================================="
echo ""

# Verifica esecuzione come root
if [ "$EUID" -ne 0 ]; then 
    print_error "Esegui questo script come root:"
    echo "  sudo bash install.sh"
    exit 1
fi

# Informazioni sistema
print_info "Hostname: $(hostname)"
print_info "IP locale: $(hostname -I | awk '{print $1}')"
if command -v lsb_release &> /dev/null; then
    print_info "Sistema: $(lsb_release -d | cut -f2)"
fi
echo ""

###########################################
# 1. AGGIORNAMENTO SISTEMA E PACCHETTI BASE
###########################################
echo "=============================================="
echo "1. AGGIORNAMENTO SISTEMA"
echo "=============================================="

print_status "Aggiornamento liste pacchetti..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq

print_status "Installazione pacchetti base..."
apt-get install -y -qq curl git ufw ca-certificates

print_status "Sistema aggiornato"

###########################################
# 2. INSTALLAZIONE APACHE WEB SERVER
###########################################
echo ""
echo "=============================================="
echo "2. INSTALLAZIONE APACHE WEB SERVER"
echo "=============================================="

print_status "Installazione Apache2..."
apt-get install -y -qq apache2

# Abilita Apache all'avvio
systemctl enable apache2

# Avvia Apache
systemctl start apache2

if systemctl is-active --quiet apache2; then
    print_status "Apache installato e avviato correttamente"
else
    print_error "Errore nell'avvio di Apache"
    exit 1
fi

###########################################
# 3. INSTALLAZIONE PHP
###########################################
echo ""
echo "=============================================="
echo "3. INSTALLAZIONE PHP E ESTENSIONI"
echo "=============================================="

print_status "Installazione PHP e php-mysql..."
apt-get install -y -qq php libapache2-mod-php php-mysql

# Verifica installazione PHP
if command -v php &> /dev/null; then
    PHP_VERSION=$(php -v | head -n 1 | awk '{print $2}')
    print_status "PHP $PHP_VERSION installato correttamente"
else
    print_error "Errore nell'installazione di PHP"
    exit 1
fi

# Riavvia Apache per caricare il modulo PHP
systemctl restart apache2
print_status "Modulo PHP caricato in Apache"

###########################################
# 4. INSTALLAZIONE MYSQL SERVER
###########################################
echo ""
echo "=============================================="
echo "4. INSTALLAZIONE E CONFIGURAZIONE MYSQL"
echo "=============================================="

print_status "Installazione Database Server (MariaDB)..."

# Installa MariaDB (fork di MySQL, completamente compatibile)
apt-get install -y -qq mariadb-server mariadb-client

MYSQL_SERVICE="mariadb"
print_status "MariaDB Server installato (compatibile MySQL)"

# Abilita e avvia MySQL
systemctl enable $MYSQL_SERVICE
systemctl start $MYSQL_SERVICE

if systemctl is-active --quiet $MYSQL_SERVICE; then
    print_status "Database server avviato correttamente"
else
    print_error "Errore nell'avvio del database server"
    exit 1
fi

# Configurazione MariaDB: root senza password (standard Raspberry Pi OS)
print_status "Configurazione MariaDB con root senza password..."

# Su MariaDB, impostiamo accesso root senza password
mysql -u root <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED VIA mysql_native_password;
SET PASSWORD FOR 'root'@'localhost' = PASSWORD('');
FLUSH PRIVILEGES;
EOF

# Se il comando sopra fallisce (vecchie versioni), prova metodi alternativi
if [ $? -ne 0 ]; then
    mysql -u root -e "UPDATE mysql.user SET plugin='mysql_native_password', authentication_string='' WHERE User='root';" 2>/dev/null || true
    mysql -u root -e "UPDATE mysql.user SET Password=PASSWORD('') WHERE User='root';" 2>/dev/null || true
    mysql -u root -e "FLUSH PRIVILEGES;" 2>/dev/null || true
fi

print_status "MariaDB configurato con root senza password"

###########################################
# 5. INSTALLAZIONE TAILSCALE
###########################################
echo ""
echo "=============================================="
echo "5. INSTALLAZIONE TAILSCALE"
echo "=============================================="

print_status "Download e installazione Tailscale..."
curl -fsSL https://tailscale.com/install.sh | sh

if command -v tailscale &> /dev/null; then
    print_status "Tailscale installato correttamente"
else
    print_error "Errore nell'installazione di Tailscale"
    exit 1
fi

print_warning "IMPORTANTE: Dopo questo script, dovrai eseguire:"
print_warning "  sudo tailscale up"
print_warning "e seguire il link per autenticare il dispositivo"

###########################################
# 6. CONFIGURAZIONE FIREWALL UFW
###########################################
echo ""
echo "=============================================="
echo "6. CONFIGURAZIONE FIREWALL (UFW)"
echo "=============================================="

print_status "Reset configurazione UFW..."
ufw --force reset

print_status "Configurazione regole firewall..."

# Consenti loopback
ufw allow in on lo
ufw allow out on lo

# REGOLA CRITICA: SSH solo su interfaccia Tailscale
ufw allow in on tailscale0 to any port 22 proto tcp
print_status "SSH consentito SOLO su interfaccia tailscale0 (rete trusted)"

# Consenti HTTP (porta 80) per Apache
ufw allow 80/tcp
print_status "HTTP (porta 80) consentito per Apache"

# Consenti HTTPS (opzionale ma utile)
ufw allow 443/tcp
print_status "HTTPS (porta 443) consentito"

# Consenti porta Tailscale
ufw allow 41641/udp
print_status "Porta Tailscale (41641/UDP) consentita"

# BLOCCA SSH su altre interfacce (eth0, wlan0)
ufw deny 22/tcp
print_status "SSH negato su tutte le altre interfacce (eth0, wlan0)"

# Policy di default
ufw default deny incoming
ufw default allow outgoing

# Abilita UFW
print_status "Abilitazione firewall..."
echo "y" | ufw enable

print_status "Firewall configurato e attivato"
echo ""
ufw status verbose

###########################################
# 7. CLONAZIONE PROGETTO DA GITHUB
###########################################
echo ""
echo "=============================================="
echo "7. CLONAZIONE PROGETTO DA GITHUB"
echo "=============================================="

PROJECT_DIR="/var/www/html/laboratorio"
WEB_ROOT="/var/www/html"

# Rimuovi directory esistente
if [ -d "$PROJECT_DIR" ]; then
    print_warning "Directory $PROJECT_DIR già esistente, rimozione..."
    sudo rm -rf "$PROJECT_DIR"
fi

print_status "Clonazione repository da GitHub..."
sudo git clone https://github.com/federicomaniglio/Webapp_Laboratorio_Raspberry.git "$PROJECT_DIR"

# Verifica che la clonazione sia riuscita
if [ ! -d "$PROJECT_DIR" ]; then
    print_error "Errore nella clonazione del repository"
    exit 1
fi

print_status "Repository clonato in $PROJECT_DIR"

# Verifica presenza file principali
if [ -f "$PROJECT_DIR/index.php" ]; then
    print_status "File index.php trovato - Applicazione con auto-setup database"
else
    print_error "File index.php non trovato nel repository"
    exit 1
fi

# Imposta permessi corretti per Apache
chown -R www-data:www-data "$PROJECT_DIR"
chmod -R 755 "$PROJECT_DIR"

print_status "Permessi impostati correttamente per Apache"

###########################################
# 8. CONFIGURAZIONE APACHE
###########################################
echo ""
echo "=============================================="
echo "8. CONFIGURAZIONE APACHE"
echo "=============================================="

# Abilita mod_rewrite (utile per applicazioni PHP)
a2enmod rewrite &> /dev/null || true
print_status "Modulo rewrite abilitato"

# Crea un VirtualHost per il progetto
cat > /etc/apache2/sites-available/laboratorio.conf << 'APACHEEOF'
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    DocumentRoot /var/www/html/laboratorio
    
    <Directory /var/www/html/laboratorio>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    
    ErrorLog ${APACHE_LOG_DIR}/laboratorio_error.log
    CustomLog ${APACHE_LOG_DIR}/laboratorio_access.log combined
</VirtualHost>
APACHEEOF

# Abilita il sito
a2ensite laboratorio.conf &> /dev/null
print_status "VirtualHost laboratorio configurato"

# Disabilita il sito default
a2dissite 000-default.conf &> /dev/null || true
print_status "Sito default disabilitato"

# Test configurazione Apache
if apache2ctl configtest 2>&1 | grep -q "Syntax OK"; then
    print_status "Configurazione Apache valida"
else
    print_warning "Attenzione: possibili warning nella configurazione Apache"
fi

# Riavvia Apache
systemctl restart apache2

if systemctl is-active --quiet apache2; then
    print_status "Apache riavviato correttamente"
else
    print_error "Errore nel riavvio di Apache"
    exit 1
fi

###########################################
# 9. VERIFICA FINALE
###########################################
echo ""
echo "=============================================="
echo "9. VERIFICA CONFIGURAZIONE FINALE"
echo "=============================================="

LOCAL_IP=$(hostname -I | awk '{print $1}')

# Verifica Apache
if systemctl is-active --quiet apache2; then
    print_status "Apache: ATTIVO ✓"
else
    print_error "Apache: NON ATTIVO ✗"
fi

# Verifica MySQL/MariaDB
if systemctl is-active --quiet mysql || systemctl is-active --quiet mariadb; then
    print_status "Database Server: ATTIVO ✓"
else
    print_error "Database Server: NON ATTIVO ✗"
fi

# Verifica PHP
if command -v php &> /dev/null; then
    print_status "PHP: INSTALLATO ✓ ($(php -v | head -n 1 | awk '{print $2}'))"
else
    print_error "PHP: NON INSTALLATO ✗"
fi

# Verifica Tailscale daemon
if systemctl is-active --quiet tailscaled; then
    print_status "Tailscale daemon: ATTIVO ✓"
else
    print_warning "Tailscale daemon: AVVIALO con 'sudo tailscale up'"
fi

# Verifica UFW
if ufw status | grep -q "Status: active"; then
    print_status "UFW Firewall: ATTIVO ✓"
else
    print_error "UFW Firewall: NON ATTIVO ✗"
fi

# Verifica progetto
if [ -f "$PROJECT_DIR/index.php" ]; then
    print_status "Progetto web: PRESENTE ✓"
else
    print_error "Progetto web: FILE index.php MANCANTE ✗"
fi

# Verifica Git
if command -v git &> /dev/null; then
    print_status "Git: INSTALLATO ✓"
else
    print_error "Git: NON INSTALLATO ✗"
fi

# Test connessione MySQL
if mysql -u root -e "SELECT 1;" &> /dev/null; then
    print_status "MySQL: CONNESSIONE ROOT OK ✓"
else
    print_warning "MySQL: Verifica connessione root"
fi

###########################################
# 10. ISTRUZIONI FINALI
###########################################
echo ""
echo "=============================================="
echo "✅ INSTALLAZIONE COMPLETATA CON SUCCESSO"
echo "=============================================="
echo ""
print_info "STACK LAMP INSTALLATO:"
echo "  ✓ Apache Web Server"
echo "  ✓ PHP + php-mysql"
echo "  ✓ MariaDB Server (compatibile MySQL, root senza password)"
echo "  ✓ Git"
echo "  ✓ Tailscale VPN"
echo "  ✓ UFW Firewall"
echo ""
print_info "PROGETTO CLONATO:"
echo "  ✓ Repository: Webapp_Laboratorio_Raspberry"
echo "  ✓ Path: $PROJECT_DIR"
echo "  ✓ Auto-setup database: SI (al primo accesso)"
echo ""
print_info "CREDENZIALI DATABASE (auto-configurate dall'app):"
echo "  Database: laboratorio_raspberry"
echo "  Utente app: webapp_user"
echo "  Password: raspberry2024"
echo "  Root MySQL: NESSUNA PASSWORD"
echo ""
print_info "PROSSIMI PASSI OBBLIGATORI:"
echo ""
echo "1️⃣  Configura Tailscale:"
echo "    sudo tailscale up"
echo "    (segui il link nel browser per autenticare)"
echo ""
echo "2️⃣  Ottieni l'IP Tailscale:"
echo "    sudo tailscale ip -4"
echo ""
echo "3️⃣  Testa SSH via Tailscale:"
echo "    ssh $(whoami)@<IP-TAILSCALE>"
echo ""
echo "4️⃣  Testa il web server:"
echo "    Browser: http://<IP-TAILSCALE>"
echo "    Browser: http://$LOCAL_IP"
echo ""
print_warning "⚠️  IMPORTANTE:"
print_warning "    SSH funzionerà SOLO tramite IP Tailscale (rete trusted)!"
print_warning "    SSH da LAN/WiFi verrà bloccato dal firewall."
print_warning "    Il database si configura automaticamente al primo accesso!"
echo ""
print_info "📁 Progetto web installato in: $PROJECT_DIR"
print_info "📊 Al primo accesso, l'applicazione creerà automaticamente:"
print_info "    - Database laboratorio_raspberry"
print_info "    - Tabelle necessarie"
print_info "    - Utente webapp_user"
echo ""
echo "=============================================="
echo ""
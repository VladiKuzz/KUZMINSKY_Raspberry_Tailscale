# Laboratorio Raspberry Pi + Tailscale

**Nome:** Mario Rossi
**Matricola:** 12345678
**Corso:** Laboratorio Raspberry Pi
**Anno:** 2024/2025

---

## Descrizione

Progetto di installazione automatica di:
- Stack LAMP (Apache, PHP, MariaDB)
- Tailscale VPN
- Firewall UFW (SSH solo su tailscale0)
- Webapp da GitHub

---

## Requisiti

- VM con Debian 12 / Ubuntu 22.04 / Raspberry Pi OS
- Minimo 1 GB RAM, 10 GB disco
- Connessione internet

---

## Installazione

### 1. Clona repository
git clone https://github.com/mariorossi/ROSSI_Raspberry_Tailscale.git
cd ROSSI_Raspberry_Tailscale

### 2. Rendi eseguibile lo script
chmod +x install.sh

### 3. Esegui lo script
sudo bash install.sh

### 4. Configura Tailscale
sudo tailscale up
(segui il link per autenticare)

### 5. Ottieni IP Tailscale
sudo tailscale ip -4

---

## Componenti Installati

- **Apache** - Web server sulla porta 80
- **PHP** + php-mysql - Interprete PHP
- **MariaDB** - Database server (compatibile MySQL)
- **Git** - Version control
- **Tailscale** - VPN mesh
- **UFW** - Firewall

---

## Accesso SSH

SSH è consentito **SOLO** tramite Tailscale:

ssh pi@<IP-TAILSCALE>

Esempio: ssh pi@100.64.0.5

---

## Accesso Web Server

http://<IP-TAILSCALE>

Esempio: http://100.64.0.5

---

## Firewall

- SSH su tailscale0: ALLOW
- HTTP (80): ALLOW
- SSH su eth0/wlan0: DENY

import os
import time
import configparser
import logging
import paramiko
import requests
import mysql.connector

# Load Configuration
CONFIG_PATH = "/etc/proxmox-auto-guac/config.ini"
config = configparser.ConfigParser()
config.read(CONFIG_PATH)

# Setup Logging
LOG_PATH = "/var/log/proxmox-auto-guac.log"
logging.basicConfig(
    filename=LOG_PATH,
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s"
)

def log(msg, level="info"):
    if level == "error":
        logging.error(msg)
    else:
        logging.info(msg)
    print(msg)

def check_proxmox():
    """Check Proxmox for new VMs/containers."""
    log("Checking Proxmox for new VMs...")
    try:
        response = requests.get(
            f"{config['proxmox']['api_url']}/api2/json/cluster/resources",
            auth=(config['proxmox']['user'], config['proxmox']['password']),
            verify=False
        )
        if response.status_code == 200:
            return response.json()['data']
        else:
            log(f"Proxmox API error: {response.status_code}", "error")
    except Exception as e:
        log(f"Proxmox connection error: {e}", "error")
    return []

def configure_ubiquiti(mac, ip, hostname):
    """Configure DHCP reservation on Ubiquiti via SSH."""
    if not config['ubiquiti'].getboolean('enabled'):
        log("Skipping Ubiquiti configuration (disabled in config).")
        return

    log(f"Configuring Ubiquiti for {hostname} ({mac} -> {ip})")
    try:
        ssh = paramiko.SSHClient()
        ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        ssh.connect(
            config['ubiquiti']['host'],
            username=config['ubiquiti']['user'],
            port=int(config['ubiquiti']['port'])
        )
        cmd = f"set static-mapping {hostname} ip-address {ip} mac-address {mac}"
        ssh.exec_command(cmd)
        ssh.close()
        log(f"Ubiquiti DHCP reservation added: {hostname} -> {ip}")
    except Exception as e:
        log(f"Ubiquiti SSH error: {e}", "error")

def configure_guacamole(vm_name, ip, mac):
    """Configure Guacamole connection."""
    if not config['guacamole'].getboolean('enabled'):
        log("Skipping Guacamole configuration (disabled in config).")
        return

    log(f"Adding Guacamole connection for {vm_name} ({ip})")
    try:
        response = requests.post(
            f"{config['guacamole']['api_url']}/api/session/data/{vm_name}",
            json={"hostname": ip, "protocol": "ssh"},
            auth=(config['guacamole']['user'], config['guacamole']['password']),
            verify=False
        )
        if response.status_code == 200:
            log(f"Guacamole connection added: {vm_name} -> {ip}")
            configure_wol(vm_name, mac)
        else:
            log(f"Guacamole API error: {response.status_code}", "error")
    except Exception as e:
        log(f"Guacamole API connection error: {e}", "error")

def configure_wol(vm_name, mac):
    """Enable WOL for a Guacamole connection in MySQL."""
    log(f"Configuring WOL for {vm_name} ({mac})")
    try:
        conn = mysql.connector.connect(
            host=config['guacamole']['db_host'],
            user=config['guacamole']['db_user'],
            password=config['guacamole']['db_password'],
            database=config['guacamole']['db_name']
        )
        cursor = conn.cursor()
        cursor.execute("SELECT connection_id FROM guacamole_connection WHERE connection_name = %s", (vm_name,))
        connection_id = cursor.fetchone()
        if connection_id:
            cursor.executemany("""
                INSERT INTO guacamole_connection_parameter (connection_id, parameter_name, parameter_value)
                VALUES (%s, 'wol-mac-addr', %s), (%s, 'wol-send-packet', 'true')
            """, [(connection_id[0], mac, connection_id[0])])
            conn.commit()
            log(f"WOL configured for {vm_name}")
        conn.close()
    except Exception as e:
        log(f"MySQL WOL configuration error: {e}", "error")

def main():
    """Main loop to monitor Proxmox and configure new VMs."""
    while True:
        vms = check_proxmox()
        for vm in vms:
            mac = "AA:00:00:01:01:00"  # Placeholder: extract actual MAC
            ip = "172.16.1.100"  # Placeholder: compute based on MAC
            vm_name = vm['name']
            configure_ubiquiti(mac, ip, vm_name)
            configure_guacamole(vm_name, ip, mac)
        time.sleep(60)  # Check every 60 seconds

if __name__ == "__main__":
    main()

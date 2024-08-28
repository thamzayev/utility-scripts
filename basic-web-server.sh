#!/bin/bash

# Function to prompt for yes/no response
ask() {
    while true; do
        read -p "$1 [y/n]: " yn
        case $yn in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) echo "Please answer yes or no.";;
        esac
    done
}

# Update the system
if ask "Do you want to update the system?"; then
    sudo apt update && sudo apt upgrade -y
fi

# Enable automatic security updates
if ask "Do you want to enable automatic security updates?"; then
    sudo apt install unattended-upgrades -y
    sudo dpkg-reconfigure --priority=low unattended-upgrades
fi

# Create a non-root user
if ask "Do you want to create a non-root user?"; then
    read -p "Enter the username: " username
    sudo adduser $username
    sudo usermod -aG sudo $username
fi

# Disable root SSH login
if ask "Do you want to disable root SSH login?"; then
    sudo sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
    sudo systemctl restart sshd
fi

# Add firewall rules
if ask "Do you want to configure the firewall?"; then
    sudo apt install ufw -y
    sudo ufw allow OpenSSH
    sudo ufw allow http
    sudo ufw allow https
    read -p "Enter the IP range to allow SSH access (e.g., 192.168.0.0/24): " ssh_range
    sudo ufw allow from $ssh_range to any port 22
    sudo ufw enable
fi

# Install nginx
if ask "Do you want to install Nginx?"; then
    sudo apt install nginx -y
    sudo systemctl enable nginx
    sudo systemctl start nginx
    
    # Add site
    read -p "Enter your domain name (e.g., example.com): " domain_name
    sudo tee /etc/nginx/sites-available/$domain_name > /dev/null <<EOL
server {
    listen 80;
    server_name $domain_name www.$domain_name;

    root /var/www/$domain_name/html;
    index index.html index.htm;

    location / {
        try_files \$uri \$uri/ =404;
    }

    # Rate limiting
    limit_req_zone \$binary_remote_addr zone=mylimit:10m rate=10r/s;

    location / {
        limit_req zone=mylimit;
    }

    # Disable server tokens
    server_tokens off;
}
EOL

    sudo mkdir -p /var/www/$domain_name/html
    sudo chown -R $USER:$USER /var/www/$domain_name/html
    sudo chmod -R 755 /var/www/$domain_name

    sudo ln -s /etc/nginx/sites-available/$domain_name /etc/nginx/sites-enabled/
    sudo nginx -t
    sudo systemctl restart nginx
fi

# Configure SSL/TLS
if ask "Do you want to configure strong SSL/TLS settings for Nginx?"; then
    sudo tee -a /etc/nginx/snippets/ssl-params.conf > /dev/null <<EOL
ssl_protocols TLSv1.2 TLSv1.3;
ssl_prefer_server_ciphers on;
ssl_ciphers "EECDH+AESGCM:EDH+AESGCM:AES256+EECDH:AES256+EDH";
ssl_ecdh_curve secp384r1;
ssl_session_timeout 10m;
ssl_session_cache shared:SSL:10m;
ssl_stapling on;
ssl_stapling_verify on;
resolver 8.8.8.8 8.8.4.4 valid=300s;
resolver_timeout 5s;
EOL
    sudo sed -i "/server {/a\ include snippets/ssl-params.conf;" /etc/nginx/sites-available/$domain_name
    sudo systemctl restart nginx
fi

# Install certbot and configure SSL certificates
if ask "Do you want to install certbot and configure SSL certificates?"; then
    sudo apt install certbot python3-certbot-nginx -y
    sudo certbot --nginx -d $domain_name -d www.$domain_name
    sudo systemctl restart nginx

    # Add certbot to cron
    echo "0 0,12 * * * root /usr/bin/certbot renew --quiet" | sudo tee -a /etc/crontab > /dev/null
fi

# Install MySQL and secure it
if ask "Do you want to install and secure MySQL?"; then
    sudo apt install mysql-server -y
    sudo mysql_secure_installation
fi

# Install PHP and common PHP extensions
if ask "Do you want to install PHP and common PHP extensions?"; then
    sudo apt install php-fpm php-mysql php-cli php-curl php-gd php-xml php-mbstring -y
fi

# Install and enable fail2ban for SSH and Nginx
if ask "Do you want to install and configure fail2ban?"; then
    sudo apt install fail2ban -y
    sudo tee /etc/fail2ban/jail.local > /dev/null <<EOL
[sshd]
enabled = true

[nginx-http-auth]
enabled = true
EOL
    sudo systemctl enable fail2ban
    sudo systemctl start fail2ban
fi

# Install Zabbix agent
if ask "Do you want to install the Zabbix agent?"; then
    sudo apt install zabbix-agent -y
    sudo systemctl enable zabbix-agent
    sudo systemctl start zabbix-agent
fi

echo "Security setup complete!"

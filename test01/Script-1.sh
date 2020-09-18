#!/bin/bash
locale=en_US.UTF-8
ssh_port=2498
user=serviceuser
group=service
echo "Hello, World!"
sudo cp /etc/localtime /etc/localtime.bak
sudo ln -sf /usr/share/zoneinfo/Europe/Moscow /etc/localtime
sudo locale-gen $locale
sudo update-locale LANG=$locale
#sudo sed -i "s/.*Port.*/Port $ssh_port/" /etc/ssh/sshd_config
#sudo sed -i "s/.*PermitRootLogin.*/PermitRootLogin no/" /etc/ssh/sshd_config
if  [ -z "$(grep -E "^PermitRootLogin no" /etc/ssh/sshd_config)" ]
  then
    sudo sed -i "0,/.*PermitRootLogin.*/s//PermitRootLogin no/" /etc/ssh/sshd_config
    sudo service sshd restart
  else 
    echo "Nothing do"
fi

if [ -z "$(grep -E "^$group:" /etc/group)" ]
    then
          sudo groupadd $group
fi

if [ -z "$(grep -E "^$user:" /etc/passwd)" ]
  then
    sudo useradd $user -g $group -s /bin/bash -d /home/$user -p $(openssl passwd -6 service)
fi

if ! [ -d /home/$user ]
  then
    sudo mkdir /home/$user/
fi

sudo chown -R $user:$group /home/$user
#sudo usermod -a -G sudo $user
if ! [ -f /etc/sudoers.d/$user ]
  then
    echo "$user ALL=/usr/sbin/service * start" | sudo tee /etc/sudoers.d/$user > /dev/null
    echo "$user ALL=/usr/sbin/service * stop" | sudo tee -a /etc/sudoers.d/$user > /dev/null
    echo "$user ALL=/usr/sbin/service * restart" | sudo tee -a /etc/sudoers.d/$user > /dev/null
fi
#sudo apt update
#sudo apt upgrade -y
if [ -z $(which nginx) ]
  then
    sudo apt install -y nginx
fi

if [ "$(systemctl is-enabled nginx)" == "disabled" ]
  then
    sudo systemctl enable nginx
fi

if [ -z $(which monit) ]
  then
    sudo apt install -y monit
fi

if ! [ -f /lib/systemd/system/monit.service ]
  then
    cat << EOF | sudo tee /lib/systemd/system/monit.service > /dev/null
 [Unit]
 Description=Pro-active monitoring utility for unix systems
 After=network-online.target
 Documentation=man:monit(1) https://mmonit.com/wiki/Monit/HowTo

 [Service]
 Type=simple
 KillMode=process
 ExecStart=/usr/bin/monit -I
 ExecStop=/usr/bin/monit quit
 ExecReload=/usr/bin/monit reload
 Restart = on-abnormal
 StandardOutput=null

 [Install]
 WantedBy=multi-user.target
EOF
  sudo systemctl daemon-reload
fi

if [ "$(systemctl is-enabled monit)" == "disabled" ]
  then
    sudo systemctl enable monit
fi

echo -e "set httpd\n\t port 2812\n\t use address 127.0.0.1\n\t allow devops:test" | sudo tee /etc/monit/conf-available/web > /dev/null
sudo ln -sf /etc/monit/conf-available/web /etc/monit/conf-enabled/web
sudo systemctl restart monit
cat << EOF | sudo tee /etc/nginx/sites-available/monit > /dev/null
server {
  listen 80;
  server_name $(hostname -I | awk '{ print $1 }');

  location /monit/ {
    rewrite ^/monit/(.*) /\$1 break;
    proxy_pass http://127.0.0.1:2812;
    proxy_set_header Host \$host;
  }
}
EOF
sudo ln -sf /etc/nginx/sites-available/monit /etc/nginx/sites-enabled/monit
sudo service nginx restart

echo "------Configure UFW------"
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow "Nginx HTTP"
sudo ufw allow OpenSSH
sudo ufw allow $ssh_port/tcp
sudo ufw allow 2812/tcp
sudo ufw --force enable
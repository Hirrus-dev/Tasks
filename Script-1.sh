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
sudo sed -i "s/.*PermitRootLogin.*/PermitRootLogin no/" /etc/ssh/sshd_config
sudo service sshd restart
sudo groupadd $group
sudo useradd $user -g $group -s /bin/bash -d /home/$user -p $(openssl passwd -6 service)
sudo mkdir -p /home/$user/
sudo chown -R $user:$group /home/$user
#sudo usermod -a -G sudo $user
echo "$user ALL=/usr/sbin/service * start" | sudo tee /etc/sudoers.d/$user > /dev/null
echo "$user ALL=/usr/sbin/service * stop" | sudo tee -a /etc/sudoers.d/$user > /dev/null
echo "$user ALL=/usr/sbin/service * restart" | sudo tee -a /etc/sudoers.d/$user > /dev/null
#sudo cat /etc/sudoers.d/$user
sudo apt update
sudo apt upgrade -y
sudo apt install -y nginx
sudo systemctl enable nginx
sudo apt install -y monit
sudo systemctl enable monit
echo -e "set httpd\n\t port 2812\n\t use address 127.0.0.1\n\t allow devops:test" | sudo tee /etc/monit/conf-available/web > /dev/null
sudo ln -sf /etc/monit/conf-available/web /etc/monit/conf-enabled/web
sudo service monit restart
sudo bash -c 'cat <<EOF > /etc/nginx/sites-available/monit
server {
  listen 80;
  server_name 192.168.12.201;

  location /monit/ {
    rewrite ^/monit/(.*) /$1 break;
    proxy_pass http://127.0.0.1:2812;
    proxy_set_header Host $host;
  }
}
EOF'
sudo ln -sf /etc/nginx/sites-available/monit /etc/nginx/sites-enabled/monit
sudo service nginx restart
provider "aws" {
  region     = "us-east-1"
  access_key = "YOURACESSKEY"
  secret_key = "YOURSECRETKEY"
}

resource "aws_vpc" "prod-vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "dev"
  }
}


resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.prod-vpc.id
}

resource "aws_route_table" "prod-route-table" {
  vpc_id = aws_vpc.prod-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  route {
    ipv6_cidr_block = "::/0"
    gateway_id      = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "dev"
  }
}

resource "aws_subnet" "subnet-1" {
  vpc_id            = aws_vpc.prod-vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1b"
  tags = {
    Name = "Prod-subnet"
  }
}

# Associate Subnet with Route Table 
resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.subnet-1.id
  route_table_id = aws_route_table.prod-route-table.id
}

resource "aws_security_group" "allow_web" {
  name        = "allow_web_traffic"
  description = "Allow web inbound traffic"
  vpc_id      = aws_vpc.prod-vpc.id

  ingress {
    description = "HTTPs traffic"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]

  }
  ingress {
    description = "HTTP traffic"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]

  }
  ingress {
    description = "SSH traffic"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]

  }
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "allow_web"
  }
}

# Create a network interface with an ip in the subnet create earlier
resource "aws_network_interface" "web-server-nic" {
  subnet_id       = aws_subnet.subnet-1.id
  private_ips     = ["10.0.1.50"]
  security_groups = [aws_security_group.allow_web.id]
}

# Assign an elastic IP to the network interface
resource "aws_eip" "one" {
  vpc                       = true
  network_interface         = aws_network_interface.web-server-nic.id
  associate_with_private_ip = "10.0.1.50"
  depends_on = [
    aws_internet_gateway.gw
  ]
}

# This allows you to output specific properties without you having to go to the aws website to check it
output "server_public_ip" {
  value = aws_eip.one.public_ip
}

resource "aws_instance" "web-server-instance" {
  ami               = "ami-07d02ee1eeb0c996c"
  instance_type     = "t2.micro"
  availability_zone = "us-east-1b"
  key_name          = "YOURAWSKEY" # Change this to your AWS key file name (without the file extension)

  network_interface {
    device_index         = 0
    network_interface_id = aws_network_interface.web-server-nic.id
  }

  # Install Linux updates and apache
  user_data = <<-EOF
        #!bin/bash
        sudo apt update -y
        sudo apt upgrade -y
        sudo apt install apache2 -y
        sudo systemctl start apache2.service 
        sudo apt install git -y
        sudo timedatectl set-timezone America/Toronto

        #php installation, downloading GPG key, and storing PPA repo in a file
        sudo apt -y install lsb-release apt-transport-https ca-certificates
        sudo wget -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg
        echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" | sudo tee /etc/apt/sources.list.d/php.list
        sudo apt update
        sudo apt upgrade -y
        sudo apt install php7.4 php7.4-apcu php7.4-mysqli -y

        #php Adding Error logs and giving root user access to private folders. 
        sudo mkdir /var/log/httpd
        sudo mkdir /var/www/private
        sudo chown admin:root /var/www/private
        sudo chown admin:root /var/www/html
        sudo apt install php libapache2-mod-php -y

        #Spelling
        sudo apt-get install libaspell15 -y
        sudo apt-get install php7.4-pspell

        #Browser cap
        cd /etc/php/7.4/mods-available
        sudo wget –O browscap.ini http://browscap.org/stream?q=Lite_PHP_BrowsCapINI
        sudo systemctl reload apache2.service 

        #Get our custom apache/security conf files and overwrite the ones in the standard apache installation"
        sudo tar -zxvf automation.tar.gz
        sudo mv /apache2.conf /etc/apache2/
        sudo mv automation-main-228c9dd7bdfdf8b2341eaec782177982d0201891/security.conf /etc/apache2/conf-enabled/
        
        #Download YOUR MODULES FROM  Repo
        sudo tar -zxvf AllModules.tar.gz
        sudo mv AllModules-main-c37cda7c4619f1c3e407359e441a76fe80de5199 /var/www/
        sudo mv /var/www/html/AllModules-main-c37cda7c4619f1c3e407359e441a76fe80de5199 /var/www/html/AllModules
        
        #Install certbot as a snap on debian
        sudo apt install snapd -y
        sudo snap install core
        sudo snap refresh core

        #Set up and Allow Https through the firewall
        sudo apt-get install ufw
        sudo ufw allow in "WWW Full"
        sudo ufw deny www
        sudo ufw allow https
        sudo ufw --force enable
        sudo service apache2 restart

        #Install certbot
        sudo snap install --classic certbot
        sudo ln -s /snap/bin/certbot /usr/bin/certbot
        sudo service apache2 restart
        
        #Obtain an SSL Certificate
        sudo certbot --apache -n --agree-tos --apache  -d yourdomain.com -m yourname@email.com

        #note: Ssl certification currently doesnt work for multiple domains. 
        #sudo certbot --apache -n --agree-tos --apache --cert-name yourdomain.com -m yourname@email.com

        #Verify certbot Auto-Renewal
        sudo certbot renew --dry-run
      EOF
  tags = {
    Name = "aws_tf"
  }
}

output "server_private_ip" {
  value = aws_instance.web-server-instance.private_ip
}

output "server_id" {
  value = aws_instance.web-server-instance.id
}

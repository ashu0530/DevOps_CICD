provider "aws" {
    profile = "ashu"
    region = "us-east-1"
}

resource "aws_default_vpc" "AWS_VPC_DEFAULT" {
    tags = {
        Name = "Default VPC"
    }
}


resource "aws_security_group" "Ansible_Firewall" {
    name        = "Ansible_Firewall_SG"
    description = "allow ssh and docker and some custom port"
    vpc_id      =  aws_default_vpc.AWS_VPC_DEFAULT.id


    ingress {
        description = "inbound_ssh_port"
        from_port = 22
        to_port = 22
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        description = "inbound_custom_port"
        from_port = 8080
        to_port = 9000
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        description = "inbound_http_port"
        from_port = 80
        to_port = 80
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
    
    ingress {
        description = "inbound_https_port"
        from_port = 443
        to_port = 443
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
    
    egress {
        description = "All traffic outbound"
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]

    }
    tags = {
      "Name" = "Jenkins_SG"
    }

  
}
    output "Ansible_SG_INFO" {
        value = aws_security_group.Ansible_Firewall.name
      
}

resource "tls_private_key" "ansible_key" {
    algorithm = "RSA"
    rsa_bits = 4096
}

resource "aws_key_pair" "ansible_key_pair" {
    key_name = "ansible_key"
    public_key = "${tls_private_key.ansible_key.public_key_openssh}"
    depends_on = [
      tls_private_key.ansible_key
    ]
}
resource "local_file" "Save_Key" {
    content = "${tls_private_key.ansible_key.private_key_pem}"
    filename = "ansible_key.pem"
    depends_on = [
      tls_private_key.ansible_key, aws_key_pair.ansible_key_pair
    ]
  
}



#instance creation

resource "aws_instance" "Ansible_instance_creation" {
    ami = "${var.ami}"
    instance_type = "${var.instance_type}"
    key_name = aws_key_pair.ansible_key_pair.key_name
    security_groups = [ "${aws_security_group.Ansible_Firewall.name}"]
    availability_zone = "us-east-1a"

    user_data = <<-EOL
    #!/bin/bash

    useradd ansadmin
    echo "ansadmin   ALL=(ALL)   NOPASSWD: ALL" | tee -a /etc/sudoers
    mkdir -p /opt/docker
    chown ansadmin:ansadmin /opt/docker
    sed -i "/^[^#]*PasswordAuthentication[[:space:]]no/c\PasswordAuthentication yes" /etc/ssh/sshd_config
    echo "PermitRootLogin yes" | tee -a /etc/ssh/sshd_config
    service sshd reload
    systemctl restart sshd
    systemctl restart ssh
    

    


    EOL
    connection {
      type = "ssh"
      user = "ec2-user"
      private_key = tls_private_key.ansible_key.private_key_pem
      host = aws_instance.Ansible_instance_creation.public_ip
    }
provisioner "file" {
    source      = "Dockerfile"
    destination = "/tmp/Dockerfile"
  }

provisioner "file" {
    source      = "regappdeployk8s.yml"
    destination = "/tmp/regappdeployk8s.yml"
  }

provisioner "file" {
    source      = "regappbuild.yml"
    destination = "/tmp/regappbuild.yml"
  }


provisioner "remote-exec" {
    inline = [

        "sudo hostnamectl set-hostname ansible-server",
        "sudo amazon-linux-extras install ansible2 -y",
        "sleep 5",
        "sudo yum install docker -y",
        "sudo usermod -aG docker ansadmin",
        "sleep 5",
        "sudo systemctl start docker",
        "sudo systemctl enable docker",
        "sudo chmod 777 /var/run/docker.sock",
        "sudo cp /tmp/Dockerfile  /opt/docker/",
        "sudo cp /tmp/regappdeployk8s.yml  /opt/docker/",
        "sudo cp /tmp/regappbuild.yml  /opt/docker/",
        "sudo chown ansadmin:ansadmin /opt/docker/regappdeployk8s.yml",
        "sudo chown ansadmin:ansadmin /opt/docker/regappbuild.yml",
        "sudo chown ansadmin:ansadmin /opt/docker/Dockerfile.yml",



        
        ]
}
    tags = {
      "Name" = "AWS_Instance_Ansible"
}

}

output "Instance_id_Ansible" {
    value = aws_instance.Ansible_instance_creation.id
}
output "Ansible_IP" {
    value = aws_instance.Ansible_instance_creation.public_ip
}

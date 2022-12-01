provider "aws" {
    profile = "ashu"
    region = "us-east-1"
}

resource "aws_default_vpc" "AWS_VPC_DEFAULT" {
    tags = {
        Name = "Default VPC"
    }
}

resource "aws_security_group" "Kubernetes_Firewall" {
    name        = "Kubernetes_Firewall_SG"
    description = "allow ssh and Kubernetes PORT"
    vpc_id      =  aws_default_vpc.AWS_VPC_DEFAULT.id


    ingress {
        description = "inbound_ssh_port"
        from_port = 22
        to_port = 22
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        description = "inbound_jenkins_port"
        from_port = 8080
        to_port = 8080
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
    
    ingress {
        description = "Inbound Kubernetes nodeport"
        from_port = 30000
        to_port = 32767
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
      "Name" = "Kubernetes_SG"
    }

  
}
    output "Kubernetes_SG_INFO" {
        value = aws_security_group.Kubernetes_Firewall.name
      
}


resource "tls_private_key" "Kubernetes_key" {
    algorithm = "RSA"
    rsa_bits = 4096
}

resource "aws_key_pair" "Kubernetes_key_pair" {
    key_name = "Kubernetes_key"
    public_key = "${tls_private_key.Kubernetes_key.public_key_openssh}"
    depends_on = [
      tls_private_key.Kubernetes_key
    ]
}
resource "local_file" "Save_Key" {
    content = "${tls_private_key.Kubernetes_key.private_key_pem}"
    filename = "Kubernetes_key.pem"
    depends_on = [
      tls_private_key.Kubernetes_key, aws_key_pair.Kubernetes_key_pair
    ]
  
}

#instance creation

resource "aws_instance" "Kubernetes_instance_creation" {
    ami = "${var.ami}"
    instance_type = "${var.instance_type}"
    key_name = aws_key_pair.Kubernetes_key_pair.key_name
    security_groups = [ "${aws_security_group.Kubernetes_Firewall.name}"]
    availability_zone = "us-east-1a"

    user_data = <<-EOL
    #!/bin/bash 
    apt-get -y update
    
    useradd -m -d /home/ansadmin/ -s /bin/bash -G sudo ansadmin

    echo "ansadmin   ALL=(ALL)   NOPASSWD: ALL" | tee -a /etc/sudoers
    sed -i "/^[^#]*PasswordAuthentication[[:space:]]no/c\PasswordAuthentication yes" /etc/ssh/sshd_config
    echo "PermitRootLogin yes" | tee -a /etc/ssh/sshd_config
    service sshd reload
    systemctl restart sshd
    systemctl restart ssh

    mkdir -p /etc/apt/keyrings
    
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

    echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    

    
    sleep 10
    cd




    
    


    EOL
    
    connection {
      type = "ssh"
      user = "ubuntu"
      private_key = tls_private_key.Kubernetes_key.private_key_pem
      host = aws_instance.Kubernetes_instance_creation.public_ip
    }

provisioner "file" {
    source      = "regapp-deployment.yml"
    destination = "/tmp/regapp-deployment.yml"
  }

provisioner "file" {
    source      = "regapp-service.yml"
    destination = "/tmp/regapp-service.yml"
  }


provisioner "remote-exec" {
    inline = [
    "sleep 10",    
    "sudo apt-get -y update",
    "curl -LO https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl",
    "chmod +x ./kubectl",
    "sudo mv ./kubectl /usr/local/bin/kubectl",
    "sudo apt-get -y install ca-certificates",
    "sudo apt-get -y install curl",
    "sudo apt-get -y install gnupg",
    "sudo apt-get -y install lsb-release",
    "sudo apt-get -y install net-tools", 
    
    "sleep 10", 


    "sudo apt-get -y update",

    "sleep 10", 


    "sudo apt-get -y install docker-ce docker-ce-cli containerd.io docker-compose-plugin", 

    "sudo groupadd docker",
    "sudo usermod -aG docker $USER",
    "sudo systemctl enable docker",
    
    "git clone https://github.com/Mirantis/cri-dockerd.git",


    "wget https://storage.googleapis.com/golang/getgo/installer_linux",
    "chmod +x ./installer_linux",
    "./installer_linux",
    ". /home/ubuntu/.bash_profile",

    "cd /home/ubuntu/cri-dockerd/",
    "mkdir bin",
    "go build -o bin/cri-dockerd",
    "mkdir -p /usr/local/bin",
    "sudo install -o root -g root -m 0755 bin/cri-dockerd /usr/local/bin/cri-dockerd",

    "sudo cp -a packaging/systemd/* /etc/systemd/system",
    "sudo sed -i -e 's,/usr/bin/cri-dockerd,/usr/local/bin/cri-dockerd,' /etc/systemd/system/cri-docker.service",
    "sudo systemctl daemon-reload",
    "sudo systemctl enable cri-docker.service",
    "sudo systemctl enable --now cri-docker.socket",
    "cd /home/ubuntu/",



    "curl -Lo minikube https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64",
    "chmod +x minikube",
    "sudo mv minikube /usr/local/bin",
    "sudo apt-get  -y install conntrack",
    "VERSION='v1.24.1'",
    "wget https://github.com/kubernetes-sigs/cri-tools/releases/download/$VERSION/crictl-$VERSION-linux-amd64.tar.gz",
    "sudo tar zxvf crictl-$VERSION-linux-amd64.tar.gz -C /usr/local/bin",
    "rm -f crictl-$VERSION-linux-amd64.tar.gz",
    "sudo chmod 777 /var/run/docker.sock",
    "sudo minikube start --vm-driver=none",
    "curl https://docs.projectcalico.org/manifests/calico-typha.yaml -o calico.yml",
    "sudo kubectl apply -f calico.yml",
    
    "sudo cp /tmp/regapp-deployment.yml  /root/",
    "sudo cp /tmp/regapp-service.yml  /root/",

    ] 
}




    tags = {
      "Name" = "AWS_Instance_Kubernetes"
    }
}

output "Instance_id_Kubernetes" {
    value = aws_instance.Kubernetes_instance_creation.id
}
output "Kubernetes_IP" {
    value = aws_instance.Kubernetes_instance_creation.public_ip
}

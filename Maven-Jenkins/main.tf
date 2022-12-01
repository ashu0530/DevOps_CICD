provider "aws" {
    profile = "ashu"
    region = "us-east-1"
}

#use default Virtual private network
resource "aws_default_vpc" "AWS_VPC_DEFAULT" {
    tags = {
        Name = "Default VPC"
    }
}

#create a resource for jenkins
resource "aws_security_group" "Jenkins_Firewall" {
    name        = "Jenkins_Firewall_SG"
    description = "allow SSH and Jenkins PORT"
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
    output "Jenkins_SG_INFO" {
        value = aws_security_group.Jenkins_Firewall.name
      
}

#Create a key for instance
resource "tls_private_key" "Jenkins_key" {
    algorithm = "RSA"
    rsa_bits = 4096
}

resource "aws_key_pair" "Jenkins_key_pair" {
    key_name = "Jenkins_key"
    public_key = "${tls_private_key.Jenkins_key.public_key_openssh}"
    depends_on = [
      tls_private_key.Jenkins_key
    ]
}
resource "local_file" "Save_Key" {
    content = "${tls_private_key.Jenkins_key.private_key_pem}"
    filename = "Jenkins_key.pem"
    depends_on = [
      tls_private_key.Jenkins_key, aws_key_pair.Jenkins_key_pair
    ]
  
}


#instance creation

resource "aws_instance" "Jenkins_instance" {
    ami = "${var.ami}"
    instance_type = "${var.instance_type}"
    key_name = aws_key_pair.Jenkins_key_pair.key_name
    security_groups = [ "${aws_security_group.Jenkins_Firewall.name}"]
    availability_zone = "${var.availability_zone}"


    #This will run via root power during sucessfully bootup of instance 
    user_data = <<-EOL
    #!/bin/bash 
    
    
    
    cd /opt
    wget https://dlcdn.apache.org/maven/maven-3/3.8.6/binaries/apache-maven-3.8.6-bin.tar.gz
    tar -xvzf apache-maven-3.8.6-bin.tar.gz
    mv apache-maven-3.8.6  maven

    echo "JAVA_HOME=/usr/lib/jvm/java-11-openjdk-11.0.16.0.8-1.amzn2.0.1.x86_64" | tee -a /root/.bashrc
    echo "JAVA_HOME=/usr/lib/jvm/java-11-openjdk-11.0.16.0.8-1.amzn2.0.1.x86_64" | tee -a /root/.bash_profile

    echo "M2_HOME=/opt/maven" | sudo tee -a /root/.bashrc
    echo "M2_HOME=/opt/maven" | sudo tee -a /root/.bash_profile

    echo "M2=/opt/maven/bin" | sudo tee -a /root/.bashrc
    echo "M2=/opt/maven/bin" | sudo tee -a /root/.bash_profile

    echo "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/root/bin:/usr/lib/jvm/java-11-openjdk-11.0.16.0.8-1.amzn2.0.1.x86_64:/opt/maven:/opt/maven/bin" | sudo tee -a /root/.bashrc
    echo "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/root/bin:/usr/lib/jvm/java-11-openjdk-11.0.16.0.8-1.amzn2.0.1.x86_64:/opt/maven:/opt/maven/bin" | sudo tee -a /root/.bash_profile

    
    
    echo "JAVA_HOME=/usr/lib/jvm/java-11-openjdk-11.0.16.0.8-1.amzn2.0.1.x86_64" | tee -a /home/ec2-user/.bashrc
    echo "JAVA_HOME=/usr/lib/jvm/java-11-openjdk-11.0.16.0.8-1.amzn2.0.1.x86_64" | tee -a /home/ec2-user/.bash_profile

    echo "M2_HOME=/opt/maven" | sudo tee -a /home/ec2-user/.bashrc
    echo "M2_HOME=/opt/maven" | sudo tee -a /home/ec2-user/.bash_profile

    echo "M2=/opt/maven/bin"  | sudo tee -a /home/ec2-user/.bashrc
    echo "M2=/opt/maven/bin"  | sudo tee -a /home/ec2-user/.bash_profile
    
    echo "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/root/bin:/usr/lib/jvm/java-11-openjdk-11.0.16.0.8-1.amzn2.0.1.x86_64:/opt/maven:/opt/maven/bin" | sudo tee -a /home/ec2-user/.bashrc
    echo "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/root/bin:/usr/lib/jvm/java-11-openjdk-11.0.16.0.8-1.amzn2.0.1.x86_64:/opt/maven:/opt/maven/bin" | sudo tee -a /home/ec2-user/.bash_profile

    

    source /root/.bashrc
    source /root/.bash_profile

    source /home/ec2-user/.bashrc
    source /home/ec2-user/.bash_profile

    echo $PATH
    
    EOL

    connection {
      type = "ssh"
      user = "ec2-user"
      private_key = tls_private_key.Jenkins_key.private_key_pem
      host = aws_instance.Jenkins_instance.public_ip
    }

#use provisioner remote execution for installing jenkins and starting the service
provisioner "remote-exec" {
    inline = [
     
      "sudo hostnamectl set-hostname jenkins-server",
      "sudo amazon-linux-extras install java-openjdk11 -y",
      "sudo yum install git -y",
      "sudo wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo",
      "sudo rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io.key",
      "sudo yum install jenkins -y",

      "sleep 10",

      "sudo systemctl start jenkins",
      "sudo systemctl enable jenkins",
      


    ]
}
    tags = {
      "Name" = "AWS_Instance_Jenkins"
    }
}

resource "null_resource" "ChromeOpen"  {
    provisioner "local-exec" {
        command = "start chrome ${aws_instance.Jenkins_instance.public_ip}"  
     }
     depends_on = [
       aws_instance.Jenkins_instance,
     ]
}

output "Instance_id_jenkins" {
    value = aws_instance.Jenkins_instance.id
}
output "Jenkins_IP" {
    value = aws_instance.Jenkins_instance.public_ip
}






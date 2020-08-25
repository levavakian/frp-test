provider "aws" {
  region = "us-east-2"
}

variable "server_port" {
  description = "The port the server will use for HTTP requests"
  type        = number
  default     = 7000
}

variable "vhost_port" {
  description = "The port the server will use for HTTP requests"
  type        = number
  default     = 80
}

resource "aws_key_pair" "ssh-key" {
  key_name   = "ssh-key"
  public_key = file("/root/.ssh/id_rsa.pub")
}

resource "aws_security_group" "instance" {
  name = "terraform-example-instance"
  ingress {
    from_port   = var.server_port
    to_port     = var.server_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = var.vhost_port
    to_port     = var.vhost_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "example" {
  ami           = "ami-07c8bc5c1ce9598c3"
  instance_type = "t2.micro"
  vpc_security_group_ids = [aws_security_group.instance.id]

  user_data = <<-EOF
              #!/bin/bash
              sudo yum update -y
              sudo amazon-linux-extras install docker
              sudo service docker start
              sudo usermod -a -G docker ec2-user
              sudo docker run -d --network=host levavakian/frp ./frps --bind_port "${var.server_port}" --vhost_http_port "${var.vhost_port}"
              EOF
  key_name = "ssh-key"

  tags = {
    Name = "terraform-example"
  }
}

output "public_ip" {
  value       = aws_instance.example.public_ip
  description = "The public IP of the web server"
}
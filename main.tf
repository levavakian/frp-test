provider "aws" {
  region = "us-east-2"
}

variable "server_port" {
  description = "The port the server will use for HTTP requests"
  type        = number
  default     = 50
}

variable "server_port_https" {
  description = "The port the server will use for HTTP requests"
  type        = number
  default     = 60
}

variable "public_port" {
  description = "The port the server will use for HTTP requests"
  type        = number
  default     = 80
}

variable "public_port_https" {
  description = "The port the server will use for HTTP requests"
  type        = number
  default     = 443
}

resource "aws_key_pair" "ssh-key" {
  key_name   = "ssh-key"
  public_key = file("/root/.ssh/id_rsa.pub")
}

# Create a VPC to launch our instances into
resource "aws_vpc" "default" {
  cidr_block = "10.0.0.0/16"
}

# Create an internet gateway to give our subnet access to the outside world
resource "aws_internet_gateway" "default" {
  vpc_id = aws_vpc.default.id
}

# Grant the VPC internet access on its main route table
resource "aws_route" "internet_access" {
  route_table_id         = aws_vpc.default.main_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.default.id
}

# Create a subnet to launch our instances into
resource "aws_subnet" "default" {
  vpc_id                  = aws_vpc.default.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
}

# A security group for the ELB so it is accessible via the web
resource "aws_security_group" "elb" {
  name        = "terraform_example_elb"
  description = "Used in the terraform"
  vpc_id      = aws_vpc.default.id

  # HTTP access from anywhere
  ingress {
    from_port   = var.public_port
    to_port     = var.public_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTP access from anywhere
  ingress {
    from_port   = var.public_port_https
    to_port     = var.public_port_https
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Our default security group to access
# the instances over SSH and HTTP
resource "aws_security_group" "default" {
  name        = "terraform_example"
  description = "Used in the terraform"
  vpc_id      = aws_vpc.default.id

  # SSH access from anywhere
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTP access from the VPC
  ingress {
    from_port   = var.server_port
    to_port     = var.server_port
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  ingress {
    from_port   = var.server_port_https
    to_port     = var.server_port_https
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_elb" "web" {
  name = "terraform-example-elb"

  subnets         = [aws_subnet.default.id]
  security_groups = [aws_security_group.elb.id]
  instances       = [aws_instance.web.id]

  listener {
    instance_port     = var.server_port
    instance_protocol = "http"
    lb_port           = var.public_port
    lb_protocol       = "http"
  }

  listener {
    instance_port     = var.server_port_https
    instance_protocol = "http"
    lb_port           = var.public_port_https
    lb_protocol       = "http"
  }
}

resource "aws_instance" "web" {
  # The connection block tells our provisioner how to
  # communicate with the resource (instance)
  instance_type = "t2.micro"

  # Lookup the correct AMI based on the region
  # we specified
  ami = "ami-07c8bc5c1ce9598c3"

  # The name of our SSH keypair we created above.
  key_name = "ssh-key"

  # Our Security group to allow HTTP and SSH access
  vpc_security_group_ids = [aws_security_group.default.id]

  # We're going to launch into the same subnet as our ELB. In a production
  # environment it's more common to have a separate private subnet for
  # backend instances.
  subnet_id = aws_subnet.default.id

  user_data = <<-EOF
              #!/bin/bash
              sudo yum update -y
              sudo amazon-linux-extras install docker
              sudo service docker start
              sudo usermod -a -G docker ec2-user
              sudo docker run -d --network=host levavakian/frp ./frps --bind_port "${var.server_port}" --vhost_http_port "${var.server_port}"
              sudo docker run -d --network=host levavakian/frp ./frps --bind_port "${var.server_port_https}" --vhost_http_port "${var.server_port_https}"
              EOF
}

output "address" {
  value = aws_elb.web.dns_name
}

output "vpcaddress" {
  value = aws_elb.web.dns_name
}
# AWS account that contains the route53 domain
provider "aws" {
  alias = "account_route53" # Specific to your setup
  region = "us-east-2"
}

provider "aws" {
  region = "us-east-2"
}

data "aws_availability_zones" "available" {
  state = "available"
}

variable "server_port" {
  description = "The port the server will use for HTTP requests"
  type        = number
  default     = 80
}

variable "server_port_https" {
  description = "The port the server will use for HTTP requests"
  type        = number
  default     = 443
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
  availability_zone = data.aws_availability_zones.available.names[0]
}

# Create a subnet to launch our instances into
resource "aws_subnet" "default2" {
  vpc_id                  = aws_vpc.default.id
  cidr_block              = "10.0.2.0/24"
  map_public_ip_on_launch = true
  availability_zone = data.aws_availability_zones.available.names[1]
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

resource "aws_lb" "web" {
  name = "terraform-example-lb"
  load_balancer_type = "network"

  subnets         = [aws_subnet.default.id, aws_subnet.default2.id]
  # security_groups = [aws_security_group.elb.id]
}

# This data source looks up the public DNS zone
data "aws_route53_zone" "public" {
  name         = "frp-test.tk"
  private_zone = false
  provider     = aws.account_route53
}

resource "aws_acm_certificate" "acm" {
  domain_name       = "frp-test.tk"
  subject_alternative_names = ["*.frp-test.tk"]
  validation_method = "DNS"
}

resource "aws_acm_certificate_validation" "cert" {
  certificate_arn         = aws_acm_certificate.acm.arn
  validation_record_fqdns = [for record in aws_route53_record.public : record.fqdn]
}

resource "aws_route53_record" "public" {
  for_each = {
    for dvo in aws_acm_certificate.acm.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.public.zone_id
}

# Standard route53 DNS record for "myapp" pointing to an ALB
resource "aws_route53_record" "myapp" {
  zone_id = data.aws_route53_zone.public.zone_id
  name    = "proxy"
  type    = "A"
  alias {
    name                   = aws_lb.web.dns_name
    zone_id                = aws_lb.web.zone_id
    evaluate_target_health = false
  }
  provider = aws.account_route53
}

resource "aws_lb_target_group" "target1" {
  name     = "httptarget"
  port     = var.server_port
  protocol = "TCP"
  vpc_id   = aws_vpc.default.id
  target_type = "ip"
  stickiness {
    enabled = false
    type = "lb_cookie"
  }
}

resource "aws_lb_target_group_attachment" "attachment1" {
  target_group_arn = aws_lb_target_group.target1.arn
  target_id        = aws_instance.web.private_ip
  port             = var.server_port
}

resource "aws_lb_listener" "listener1" {
  load_balancer_arn = aws_lb.web.arn
  port           = var.public_port
  protocol       = "TCP"

  default_action {
    target_group_arn = aws_lb_target_group.target1.id
    type = "forward"
  }
}

resource "aws_lb_target_group" "target2" {
  name     = "httpstarget"
  port     = var.server_port_https
  protocol = "TCP"
  vpc_id   = aws_vpc.default.id
  target_type = "ip"
  stickiness {
    enabled = false
    type = "lb_cookie"
  }
}

resource "aws_lb_target_group_attachment" "attachment2" {
  target_group_arn = aws_lb_target_group.target2.arn
  target_id        = aws_instance.web.private_ip
  port             = var.server_port_https
}

resource "aws_lb_listener" "listener2" {
  load_balancer_arn = aws_lb.web.arn
  port           = var.public_port_https
  protocol       = "TLS"
  certificate_arn = aws_acm_certificate_validation.cert.certificate_arn

  default_action {
    target_group_arn = aws_lb_target_group.target2.id
    type = "forward"
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
  value = aws_lb.web.dns_name
}

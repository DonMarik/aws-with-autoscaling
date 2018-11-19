provider "aws" {
  region = "eu-central-1"
  shared_credentials_file = "~/.aws/credentials"
  profile = "se-account"
}

variable "region" {
  default = "eu-central-1"
}

variable "aws_amis" {
  type = "map"
  default = { "eu-central-1" = "ami-0bdf93799014acdc4" }
}

variable "key_name" {
    type = "string"
    default = "ec2key"
}
variable "environment" {
    type = "string"
}

variable "mgmt_ips" {
    default = ["0.0.0.0/0"]
}

variable "server_port" {
  description = "The port the server will use for HTTP requests"
  default = 8080
}

data "aws_availability_zones" "all" {}

resource "tls_private_key" "ma-privkey"
{
    algorithm = "RSA"
    rsa_bits = 4096
}
resource "aws_key_pair" "ma-keypair"
{
    key_name = "${var.key_name}"
    public_key = "${tls_private_key.ma-privkey.public_key_openssh}"
}
output "private_key" {
  value = "${tls_private_key.ma-privkey.private_key_pem}"
  sensitive = true
}

resource "aws_security_group" "instance" {
  name = "terraform-example-instance"

  ingress {
    from_port = "${var.server_port}"
    to_port = "${var.server_port}"
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_launch_configuration" "ma_ec2_webserver" {
  image_id = "${lookup(var.aws_amis, var.region)}"
  instance_type = "t2.micro"
  key_name = "${aws_key_pair.ma-keypair.key_name}"
  security_groups = ["${aws_security_group.WebserverSG.id}"]

  user_data = <<-EOF
              #!/bin/bash
              echo "Hello, World" > index.html
              nohup busybox httpd -f -p "${var.server_port}" &
              EOF

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "ma_ec2_webserver" {
  launch_configuration = "ma_ec2_webserver"
  #availability_zones = ["${data.aws_availability_zones.all.names}"]
  #obsolete availability_zones = ["eu-central-1a", "eu-central-1b"]
  vpc_zone_identifier = ["${aws_subnet.pub-web-az-a.id}", "${aws_subnet.pub-web-az-b.id}"]
  load_balancers = ["${aws_elb.ma-lb-1.name}"]
  health_check_type = "ELB"
  min_size = 2
  max_size = 5

  tag {
    key = "Name"
    value = "ASG-webservers"
    propagate_at_launch = true
  }
}

resource "aws_elb" "ma-lb-1" {
    name_prefix = "${var.environment}-"
    subnets = ["${aws_subnet.pub-web-az-a.id}", "${aws_subnet.pub-web-az-b.id}"]
    health_check {
        healthy_threshold = 2
        unhealthy_threshold = 2
        timeout = 3
        target = "HTTP:${var.server_port}/"
        interval = 30
    }
    listener {
        instance_port = "${var.server_port}"
        instance_protocol = "http"
        lb_port = 80
        lb_protocol = "http"
    }
    cross_zone_load_balancing = true
    security_groups = ["${aws_security_group.LoadBalancerSG.id}"]
}

output "elb_dns_name" {
  value = "${aws_elb.ma-lb-1.dns_name}"
}


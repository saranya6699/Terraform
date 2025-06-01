provider "aws" {
  profile = var.profile
  region  = var.region-master
  alias   = "region-master"
}

provider "aws" {
  profile = var.profile
  region  = var.region-worker
  alias   = "region-worker"
}

resource "aws_vpc" "vpc_useast" {
  provider             = aws.region-master
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "master-vpc-jenkins"
  }
}

resource "aws_vpc" "vpc_uswest" {
  provider             = aws.region-worker
  cidr_block           = "192.168.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "worker-vpc-jenkins"
  }
}

data "aws_availability_zones" "azs" {
  provider = aws.region-master
  state    = "available"
}

resource "aws_subnet" "public-subnet-1" {
  provider          = aws.region-master
  vpc_id            = aws_vpc.vpc_useast.id
  availability_zone = element(data.aws_availability_zones.azs.names, 0)
  cidr_block        = "10.0.1.0/24"
  tags = {
    Name = "public-subnet-1"
  }
}

resource "aws_subnet" "public-subnet-2" {
  provider          = aws.region-master
  vpc_id            = aws_vpc.vpc_useast.id
  availability_zone = element(data.aws_availability_zones.azs.names, 1)
  cidr_block        = "10.0.2.0/24"
  tags = {
    Name = "public-subnet-2"
  }
}

resource "aws_subnet" "public-subnet" {
  provider   = aws.region-worker
  vpc_id     = aws_vpc.vpc_uswest.id
  cidr_block = "192.168.1.0/24"
  tags = {
    Name = "public-subnet"
  }
}

resource "aws_internet_gateway" "internet-gateway-east" {
  provider = aws.region-master
  vpc_id   = aws_vpc.vpc_useast.id
}

resource "aws_internet_gateway" "internet-gateway-west" {
  provider = aws.region-worker
  vpc_id   = aws_vpc.vpc_uswest.id
}

resource "aws_vpc_peering_connection" "useast-uswest" {
  provider    = aws.region-master
  peer_vpc_id = aws_vpc.vpc_uswest.id
  vpc_id      = aws_vpc.vpc_useast.id
  peer_region = var.region-worker
}

resource "aws_vpc_peering_connection_accepter" "accept-uswest" {
  provider                  = aws.region-worker
  vpc_peering_connection_id = aws_vpc_peering_connection.useast-uswest.id
  auto_accept               = true
}

resource "aws_route_table" "internet-route" {
  provider = aws.region-master
  vpc_id   = aws_vpc.vpc_useast.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.internet-gateway-east.id
  }
  route {
    cidr_block                = "192.168.1.0/24"
    vpc_peering_connection_id = aws_vpc_peering_connection.useast-uswest.id
  }
  tags = {
    Name = "Master-Region-RT"
  }
}

resource "aws_route_table_association" "set-master-default-rt-assoc" {
  provider       = aws.region-master
  subnet_id      = aws_subnet.public-subnet-1.id
  route_table_id = aws_route_table.internet-route.id
}

resource "aws_route_table" "internet-route-oregon" {
  provider = aws.region-worker
  vpc_id   = aws_vpc.vpc_uswest.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.internet-gateway-west.id
  }
  route {
    cidr_block                = "10.0.0.0/16"
    vpc_peering_connection_id = aws_vpc_peering_connection.useast-uswest.id
  }
  tags = {
    Name = "Worker-Region-RT"
  }
}

resource "aws_main_route_table_association" "set-worker-default-rt-assoc" {
  provider       = aws.region-worker
  vpc_id         = aws_vpc.vpc_uswest.id
  route_table_id = aws_route_table.internet-route-oregon.id
}

resource "aws_security_group" "jenkins-sg" {
  provider    = aws.region-master
  name        = "jenkins-sg"
  description = "Allow TCP/8080 & TCP/22"
  vpc_id      = aws_vpc.vpc_useast.id

  ingress {
    description = "Allow 22 from our public IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.external_ip]
  }

  ingress {
    description = "Allow all on port 8080"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "allow traffic from us-west-2"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["192.168.1.0/24"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "alb-sg" {
  provider    = aws.region-master
  name        = "alb-sg"
  description = "Allow 443 and traffic to Jenkins SG"
  vpc_id      = aws_vpc.vpc_useast.id

  ingress {
    description = "Allow 443 from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow 80 from anywhere for redirection"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description     = "Allow traffic to jenkins-sg"
    from_port       = 0
    to_port         = 0
    protocol        = "tcp"
    security_groups = [aws_security_group.jenkins-sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "jenkins-sg-oregon" {
  provider    = aws.region-worker
  name        = "jenkins-sg-oregon"
  description = "Allow TCP/8080 & TCP/22"
  vpc_id      = aws_vpc.vpc_uswest.id

  ingress {
    description = "Allow 22 from our public IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.external_ip]
  }

  ingress {
    description = "allow traffic from us-east-1"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.1.0/24"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}







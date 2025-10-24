terraform {
  required_version = ">= 1.6.0"
}

provider "aws" {
  region = var.region
}


# VPC

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.tags, {
    Name = "${var.env}-vpc"
  })
}


# Internet Gateway

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags = merge(var.tags, {
    Name = "${var.env}-igw"
  })
}


# Public Subnets

resource "aws_subnet" "public" {
  for_each = toset(var.public_subnets)

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value
  map_public_ip_on_launch = true
  availability_zone       = element(var.azs, index(var.public_subnets, each.value))

  tags = merge(var.tags, {
    Name = "${var.env}-public-${each.key}"
  })
}


# Private Subnets

resource "aws_subnet" "private" {
  for_each = toset(var.private_subnets)

  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value
  availability_zone = element(var.azs, index(var.private_subnets, each.value))

  tags = merge(var.tags, {
    Name = "${var.env}-private-${each.key}"
  })
}


# Elastic IP for NAT Gateway

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = merge(var.tags, {
    Name = "${var.env}-nat-eip"
  })
}


# NAT Gateway (only one)

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = element(values(aws_subnet.public)[*].id, 0) # place NAT in first public subnet

  tags = merge(var.tags, {
    Name = "${var.env}-nat-gw"
  })

  depends_on = [aws_internet_gateway.this]
}


# Route Tables


# Public route table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags = merge(var.tags, {
    Name = "${var.env}-public-rt"
  })
}

# Route: Internet Gateway for public subnets
resource "aws_route" "public_internet_access" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

# Private route table (shared for all private subnets)
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id
  tags = merge(var.tags, {
    Name = "${var.env}-private-rt"
  })
}

# Route: NAT Gateway for private subnets
resource "aws_route" "private_nat_access" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this.id
}


# Route Table Associations


# Public subnets
resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# Private subnets
resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}

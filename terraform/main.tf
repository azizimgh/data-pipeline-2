################################################################################
# Tasks: Create MSK cluster ,a producer (lambda) and a consumer (lambda)
################################################################################



################################################################################
# MSK Cluster
################################################################################
resource "aws_kms_key" "kafka_kms_key" {
  description = "Key for Apache Kafka"
}

resource "aws_cloudwatch_log_group" "kafka_log_group" {
  name = "kafka_broker_logs"
}

resource "aws_msk_configuration" "kafka_config" {
  kafka_versions    = ["3.4.0"]
  name              = "${var.global_prefix}-config"
  server_properties = <<EOF
auto.create.topics.enable = true
delete.topic.enable = true
EOF
}

resource "aws_msk_cluster" "kafka" {
  cluster_name           = var.global_prefix
  kafka_version          = "3.4.0"
  number_of_broker_nodes = 3
  broker_node_group_info {
    instance_type = "kafka.t3.small"  
    storage_info {
      ebs_storage_info {
        volume_size = 10
      }
    }
    client_subnets = [aws_subnet.private_subnet[0].id,
      aws_subnet.private_subnet[1].id,
    aws_subnet.private_subnet[2].id]
    security_groups = [aws_security_group.kafka.id]
  }
  encryption_info {
    encryption_in_transit {
      client_broker = "PLAINTEXT"
    }
    encryption_at_rest_kms_key_arn = aws_kms_key.kafka_kms_key.arn
  }
  configuration_info {
    arn      = aws_msk_configuration.kafka_config.arn
    revision = aws_msk_configuration.kafka_config.latest_revision
  }
  open_monitoring {
    prometheus {
      jmx_exporter {
        enabled_in_broker = true
      }
      node_exporter {
        enabled_in_broker = true
      }
    }
  }
  logging_info {
    broker_logs {
      cloudwatch_logs {
        enabled   = true
        log_group = aws_cloudwatch_log_group.kafka_log_group.name
      }
    }
  }
}

################################################################################
# General
################################################################################

resource "aws_vpc" "default" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
}

resource "aws_internet_gateway" "default" {
  vpc_id = aws_vpc.default.id
}

resource "aws_eip" "default" {
  depends_on = [aws_internet_gateway.default]
  domain     = "vpc"
}

resource "aws_route" "default" {
  route_table_id         = aws_vpc.default.main_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.default.id
}

resource "aws_route_table" "second_route_table" {
  vpc_id = aws_vpc.default.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.default.id
  }
}

# Enable Internet traffic for the public subnet
resource "aws_route_table_association" "public_subnet_association" {
  count          = length(data.aws_availability_zones.available.names)
  subnet_id      = element(aws_subnet.public_subnet.*.id, count.index)
  route_table_id = aws_route_table.second_route_table.id
}

################################################################################
# Subnets
################################################################################

resource "aws_subnet" "private_subnet" {
  count                   = length(var.private_cidr_blocks)
  vpc_id                  = aws_vpc.default.id
  cidr_block              = element(var.private_cidr_blocks, count.index)
  map_public_ip_on_launch = false
  availability_zone       = data.aws_availability_zones.available.names[count.index]
}

resource "aws_subnet" "public_subnet" {
  count                   = length(var.public_cidr_blocks)
  vpc_id                  = aws_vpc.default.id
  cidr_block              = element(var.public_cidr_blocks, count.index)
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[count.index]
}

################################################################################
# Security groups
################################################################################

resource "aws_security_group" "kafka" {
  name   = "${var.global_prefix}-kafka"
  vpc_id = aws_vpc.default.id
  ingress {
    from_port = 0
    to_port   = 9092
    protocol  = "TCP"
    cidr_blocks = ["10.0.1.0/24",
      "10.0.2.0/24",
    "10.0.3.0/24"]
  }
  ingress {
    from_port   = 0
    to_port     = 9092
    protocol    = "TCP"
    cidr_blocks = ["10.0.4.0/24"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

################################################################################
# Lambda
################################################################################

# Lambda function producer
resource "aws_lambda_function" "write_to_msk" {
  filename      = "write_to_msk_lambda.zip"
  function_name = "writeToMSK"
  role          = aws_iam_role.lambda_write_msk.arn
  handler       = "handler.lambda_handler"
  runtime       = "python3.8"
}

# Lambda function consumer
resource "aws_lambda_function" "read_from_msk_write_to_s3" {
  filename      = "read_from_msk_write_to_s3_lambda.zip"
  function_name = "readFromMSKWriteToS3"
  role          = aws_iam_role.lambda_read_msk_write_s3.arn
  handler       = "handler.lambda_handler"
  runtime       = "python3.8"
}

resource "aws_iam_role" "lambda_write_msk" {
  name = "lambda_write_msk_execution_role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role" "lambda_read_msk_write_s3" {
  name = "lambda_read_msk_write_s3_execution_role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_policy_attachment" "lambda_produce" {
  name       = "lambda_produce"
  roles      = [aws_iam_role.lambda_write_msk.name]
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy_attachment" "lambda_read_msk_write_s3" {
  name       = "lambda_read_msk_write_s3"
  roles      = [aws_iam_role.lambda_read_msk_write_s3.name]
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
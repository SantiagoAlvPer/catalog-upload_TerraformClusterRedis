//vpc
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
}

//internet gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
}

//subnet public
resource "aws_subnet" "public" {
  count      = length(var.public_subnet_cidr)
  vpc_id     = aws_vpc.main.id
  cidr_block = var.public_subnet_cidr[count.index]

}

//private subnet
resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidr)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidr[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]
}

//route table public
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
}

//route table private
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
}

//associations public and private
resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id

}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}


//cluster redis 
resource "aws_elasticache_cluster" "redis_cluster" {
  cluster_id           = var.redis_cluster_name
  engine               = "redis"
  node_type            = var.redis_node_type
  num_cache_nodes      = var.redis_num_nodes
  parameter_group_name = "default.redis7"
  port                 = 6379
  security_group_ids   = [aws_security_group.redis_security_group.id]
  subnet_group_name    = aws_elasticache_subnet_group.redis_subnet_group.id
}

resource "aws_elasticache_subnet_group" "redis_subnet_group" {
  name       = "${var.redis_cluster_name}-subnet-group"
  subnet_ids = aws_subnet.private[*].id
}

resource "aws_security_group" "redis_security_group" {
  name        = "${var.redis_cluster_name}-sg"
  description = "Security group for Redis cluster"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "redis for lambda"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda_security_group.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


//lambda function
resource "aws_iam_role" "lambda_role" {
  name = "${var.lambda_function_name}-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  name   = "${var.lambda_function_name}-policy"
  role   = aws_iam_role.lambda_role.id
  policy = data.aws_iam_policy_document.lambda_policy_doc.json
}

resource "aws_security_group" "lambda_security_group" {
  name        = "${var.lambda_function_name}-sg"
  description = "Security group for Lambda function"
  vpc_id      = aws_vpc.main.id
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }


}

resource "aws_lambda_function" "redis_lambda" {
  filename         = var.lambda_zip_path
  function_name    = var.lambda_function_name
  role             = aws_iam_role.lambda_role.arn
  handler          = "handlers/catalogUpdate.handler"
  runtime          = "nodejs20.x"
  timeout          = 30
  memory_size      = 128
  source_code_hash = data.archive_file.lambda_function.output_base64sha256

  vpc_config {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.lambda_security_group.id]
  }

  environment {
    variables = {
      REDIS_ENDPOINT = aws_elasticache_cluster.redis_cluster.cache_nodes[0].address
      REDIS_PORT     = aws_elasticache_cluster.redis_cluster.cache_nodes[0].port
      S3_BUCKET      = aws_s3_bucket.catalog_uploads.id
    }
  }
  depends_on = [
    aws_iam_role_policy.lambda_policy,
    data.archive_file.lambda_function,
    aws_elasticache_cluster.redis_cluster
  ]
}


resource "aws_s3_bucket" "catalog_uploads" {
  bucket        = var.s3_bucket_name
  force_destroy = true

  tags = {
    Name        = var.s3_bucket_name
    Environment = "dev"
    ManagedBy   = "Terraform"
    Purpose     = "Catalog CSV uploads for Redis cluster"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "catalog_uploads_encryption" {
  bucket = aws_s3_bucket.catalog_uploads.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "catalog_uploads_lifecycle" {
  bucket = aws_s3_bucket.catalog_uploads.id

  rule {
    id     = "delete-old-csv-files"
    status = "Enabled"

    expiration {
      days = 30
    }

    filter {
      prefix = ""
    }
  }
}


//  VPC Endpoint para S3 
resource "aws_vpc_endpoint" "s3" {
  vpc_id       = aws_vpc.main.id
  service_name = "com.amazonaws.${var.aws_region}.s3"

  vpc_endpoint_type = "Gateway"

  route_table_ids = [
    aws_route_table.private.id,
    aws_route_table.public.id
  ]

  tags = {
    Name        = "s3-vpc-endpoint"
    Environment = "Production"
    ManagedBy   = "Terraform"
  }
}

// Política para el VPC Endpoint de S3 (permite acceso completo)
resource "aws_vpc_endpoint_policy" "s3_policy" {
  vpc_endpoint_id = aws_vpc_endpoint.s3.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:*"
        Resource  = "*"
      }
    ]
  })
}


// API Gateway 
resource "aws_api_gateway_rest_api" "lambda_api" {
  name        = "${var.lambda_function_name}-api"
  description = "API Gateway for Lambda function "

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

// API Gateway Resource
resource "aws_api_gateway_resource" "catalog_resource" {
  rest_api_id = aws_api_gateway_rest_api.lambda_api.id
  parent_id   = aws_api_gateway_rest_api.lambda_api.root_resource_id
  path_part   = "catalog"
}

resource "aws_api_gateway_resource" "update_resource" {
  rest_api_id = aws_api_gateway_rest_api.lambda_api.id
  parent_id   = aws_api_gateway_resource.catalog_resource.id
  path_part   = "update"
}

//  API Gateway Method (POST)
resource "aws_api_gateway_method" "post_method" {
  rest_api_id   = aws_api_gateway_rest_api.lambda_api.id
  resource_id   = aws_api_gateway_resource.update_resource.id
  http_method   = "POST"
  authorization = "NONE"
}

// Lambda Integration
resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id             = aws_api_gateway_rest_api.lambda_api.id
  resource_id             = aws_api_gateway_resource.update_resource.id
  http_method             = aws_api_gateway_method.post_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.redis_lambda.invoke_arn
}

//  Method Response
resource "aws_api_gateway_method_response" "response_200" {
  rest_api_id = aws_api_gateway_rest_api.lambda_api.id
  resource_id = aws_api_gateway_resource.update_resource.id
  http_method = aws_api_gateway_method.post_method.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}

# Integration Response
resource "aws_api_gateway_integration_response" "response_200" {
  rest_api_id = aws_api_gateway_rest_api.lambda_api.id
  resource_id = aws_api_gateway_resource.update_resource.id
  http_method = aws_api_gateway_method.post_method.http_method
  status_code = aws_api_gateway_method_response.response_200.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = "'*'"
  }

  depends_on = [
    aws_api_gateway_integration.lambda_integration
  ]
}

// Lambda Permission for API Gateway
resource "aws_lambda_permission" "api_gateway_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.redis_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.lambda_api.execution_arn}/*/*"
}

# API Gateway Deployment
resource "aws_api_gateway_deployment" "lambda_deployment" {
  rest_api_id = aws_api_gateway_rest_api.lambda_api.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.update_resource.id,
      aws_api_gateway_method.post_method.id,
      aws_api_gateway_integration.lambda_integration.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_integration.lambda_integration,
    aws_api_gateway_integration_response.response_200
  ]
}

# API Gateway Stage (Free Tier)
resource "aws_api_gateway_stage" "prod_stage" {
  deployment_id = aws_api_gateway_deployment.lambda_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.lambda_api.id
  stage_name    = "prod"

  # Configuración para optimizar costos en capa gratuita
  xray_tracing_enabled = false # Desactivar X-Ray para evitar costos adicionales

  tags = {
    Environment = "Production"
    Tier        = "Free"
  }
}

# CloudWatch Log Group para API Gateway (opcional, dentro de capa gratuita)
resource "aws_cloudwatch_log_group" "api_gateway_logs" {
  name              = "/aws/apigateway/${var.lambda_function_name}-api"
  retention_in_days = 7
  tags = {
    Environment = "Production"
  }
}

resource "aws_api_gateway_method_settings" "all" {
  rest_api_id = aws_api_gateway_rest_api.lambda_api.id
  stage_name  = aws_api_gateway_stage.prod_stage.stage_name
  method_path = "*/*"

  settings {
    metrics_enabled        = true
    logging_level          = "OFF"
    data_trace_enabled     = false
    throttling_burst_limit = 5000
    throttling_rate_limit  = 10000
  }
}


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
  handler          = "dist/handlers/catalogUpdate.handler"
  runtime          = "nodejs20.x"
  timeout          = 30   # Capa gratuita: hasta 15 minutos por ejecución
  memory_size      = 128  # Capa gratuita: 1M solicitudes/mes y 400,000 GB-segundos
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


//S3 bucket para almacenar archivos CSV del catálogo (optimizado para capa gratuita)
resource "aws_s3_bucket" "catalog_uploads" {
  bucket        = var.s3_bucket_name
  force_destroy = true  # Permite eliminar el bucket con objetos (útil para dev/testing)

  tags = {
    Name        = var.s3_bucket_name
    Environment = "dev"
    ManagedBy   = "Terraform"
    Purpose     = "Catalog CSV uploads for Redis cluster"
  }
}

# Encriptación SSE-S3 (gratis en capa gratuita)
resource "aws_s3_bucket_server_side_encryption_configuration" "catalog_uploads_encryption" {
  bucket = aws_s3_bucket.catalog_uploads.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Bloqueo de acceso público (seguridad sin costo)
resource "aws_s3_bucket_public_access_block" "catalog_uploads_block" {
  bucket = aws_s3_bucket.catalog_uploads.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle para eliminar archivos antiguos y ahorrar espacio (30 días)
resource "aws_s3_bucket_lifecycle_configuration" "catalog_uploads_lifecycle" {
  bucket = aws_s3_bucket.catalog_uploads.id

  rule {
    id     = "delete-old-csv-files"
    status = "Enabled"

    expiration {
      days = 30  # Elimina archivos después de 30 días para ahorrar almacenamiento
    }

    filter {
      prefix = ""  # Aplica a todos los archivos
    }
  }
}


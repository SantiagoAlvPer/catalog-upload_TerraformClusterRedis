output "s3_bucket_name" {
  description = "Name of the S3 bucket for catalog uploads"
  value       = aws_s3_bucket.catalog_uploads.id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = aws_s3_bucket.catalog_uploads.arn
}

# Redis Outputs
output "redis_endpoint" {
  description = "Redis cluster endpoint with port"
  value       = "${aws_elasticache_cluster.redis_cluster.cache_nodes[0].address}:${aws_elasticache_cluster.redis_cluster.cache_nodes[0].port}"
}

output "redis_port" {
  description = "Redis cluster port"
  value       = aws_elasticache_cluster.redis_cluster.cache_nodes[0].port
}

# Lambda Outputs
output "lambda_function_arn" {
  description = "Lambda function ARN"
  value       = aws_lambda_function.redis_lambda.arn
}

output "lambda_function_name" {
  description = "Lambda function name"
  value       = aws_lambda_function.redis_lambda.function_name
}

# VPC Endpoint Outputs
output "vpc_endpoint_s3_id" {
  description = "ID del VPC Endpoint para S3"
  value       = aws_vpc_endpoint.s3.id
}

# API Gateway Outputs
output "api_gateway_url" {
  description = "URL del API Gateway para invocar la Lambda"
  value       = "${aws_api_gateway_stage.prod_stage.invoke_url}/catalog/update"
}

output "api_gateway_id" {
  description = "API Gateway ID"
  value       = aws_api_gateway_rest_api.lambda_api.id
}

output "api_gateway_stage" {
  description = "API Gateway Stage"
  value       = aws_api_gateway_stage.prod_stage.stage_name
}
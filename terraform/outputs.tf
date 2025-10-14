output "s3_bucket_name" {
  description = "Name of the S3 bucket for catalog uploads"
  value       = aws_s3_bucket.catalog_uploads.id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = aws_s3_bucket.catalog_uploads.arn
}

output "redis_endpoint" {
  description = "Redis cluster endpoint"
  value       = aws_elasticache_cluster.redis_cluster.cache_nodes[0].address
}

output "redis_port" {
  description = "Redis cluster port"
  value       = aws_elasticache_cluster.redis_cluster.cache_nodes[0].port
}

output "lambda_function_arn" {
  description = "Lambda function ARN"
  value       = aws_lambda_function.redis_lambda.arn
}

output "lambda_function_name" {
  description = "Lambda function name"
  value       = aws_lambda_function.redis_lambda.function_name
}

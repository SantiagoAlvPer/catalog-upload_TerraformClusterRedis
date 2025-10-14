variable "aws_region" {
  description = "The AWS region to deploy resources in"
  type        = string
  default     = "us-east-2"
}

variable "vpc_cidr" {
  type        = string
  description = "The CIDR block for the VPC"
  default     = "10.0.0.0/16"
}

variable "private_subnet_cidr" {
  type    = list(string)
  default = ["10.0.101.0/24", "10.0.102.0/24"]
}

variable "public_subnet_cidr" {
  type    = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24"]

}

variable "redis_cluster_name" {
  type        = string
  default     = "my-redis-cluster"
  description = "The name of the Redis cluster"
}

variable "redis_node_type" {
  type        = string
  default     = "cache.t3.micro"
  description = "The instance type for the Redis nodes"
}

variable "redis_num_nodes" {
  type        = number
  default     = 1
  description = "The number of Redis nodes"
}

variable "subnet_group_name" {
  type = string
  default = "EEE"
}

variable "lambda_zip_path" {
  type = string
  default = "../lambda_function.zip"
}

variable "lambda_function_name" {
  type = string
  default = "updateProductsFunction"
  description = "The name of the Lambda function"
}

variable "s3_bucket_name" {
  type        = string
  default     = "catalog-uploads-bucket"
  description = "S3 bucket for storing catalog CSV files"
}
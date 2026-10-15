resource "aws_s3_bucket" "app_bucket" {
  bucket        = "stackpulse-app-storage-${var.environment}-551504153839"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "block" {
  bucket                  = aws_s3_bucket.app_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "encryption" {
  bucket = aws_s3_bucket.app_bucket.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

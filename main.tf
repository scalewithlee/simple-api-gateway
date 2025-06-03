# Simple API Gateway + Lambda for learning
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# Create a simple Lambda function
resource "aws_lambda_function" "hello_world" {
  function_name = "hello-world-api"
  role          = aws_iam_role.lambda_role.arn

  # Inline code - super simple!
  filename         = "hello.zip"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  handler = "index.handler"
  runtime = "nodejs18.x"
  timeout = 10
}

# Create the Lambda code as a zip file
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "hello.zip"
  source {
    content  = <<EOF
exports.handler = async (event) => {
    console.log('Received event:', JSON.stringify(event, null, 2));

    return {
        statusCode: 200,
        headers: {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        body: JSON.stringify({
            message: 'Hello from API Gateway + Lambda!',
            timestamp: new Date().toISOString(),
            path: event.path,
            method: event.httpMethod || event.requestContext?.http?.method
        })
    };
};
EOF
    filename = "index.js"
  }
}

# IAM role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "hello-world-lambda-role"

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

# Attach basic execution policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda_role.name
}

# Create API Gateway (HTTP API - simpler than REST API)
resource "aws_apigatewayv2_api" "hello_api" {
  name          = "hello-world-api"
  protocol_type = "HTTP"
  description   = "Simple API Gateway for learning"

  # Enable CORS
  cors_configuration {
    allow_credentials = false
    allow_headers     = ["content-type"]
    allow_methods     = ["GET", "POST", "OPTIONS"]
    allow_origins     = ["*"]
    max_age           = 86400
  }
}

# Create integration between API Gateway and Lambda
resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id           = aws_apigatewayv2_api.hello_api.id
  integration_type = "AWS_PROXY"

  integration_method = "POST"
  integration_uri    = aws_lambda_function.hello_world.invoke_arn

  # Use payload format version 2.0 (newer, simpler)
  payload_format_version = "2.0"
}

# Create routes (URL paths)
resource "aws_apigatewayv2_route" "hello_get" {
  api_id    = aws_apigatewayv2_api.hello_api.id
  route_key = "GET /hello"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

resource "aws_apigatewayv2_route" "hello_post" {
  api_id    = aws_apigatewayv2_api.hello_api.id
  route_key = "POST /hello"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

# Catch-all route
resource "aws_apigatewayv2_route" "catch_all" {
  api_id    = aws_apigatewayv2_api.hello_api.id
  route_key = "ANY /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

# Create a stage (like "dev", "prod") - required for HTTP APIs
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.hello_api.id
  name        = "$default"
  auto_deploy = true

  # Optional: Add access logging
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_logs.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      protocol       = "$context.protocol"
      responseLength = "$context.responseLength"
    })
  }
}

# CloudWatch log group for API Gateway logs
resource "aws_cloudwatch_log_group" "api_logs" {
  name              = "/aws/apigateway/hello-world-api"
  retention_in_days = 7
}

# Give API Gateway permission to invoke Lambda
resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.hello_world.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.hello_api.execution_arn}/*/*"
}

# Outputs so you can test it
output "api_url" {
  description = "URL of the API Gateway"
  value       = aws_apigatewayv2_api.hello_api.api_endpoint
}

output "test_urls" {
  description = "URLs to test"
  value = {
    hello_get  = "${aws_apigatewayv2_api.hello_api.api_endpoint}/hello"
    hello_post = "${aws_apigatewayv2_api.hello_api.api_endpoint}/hello"
    catch_all  = "${aws_apigatewayv2_api.hello_api.api_endpoint}/anything/you/want"
  }
}

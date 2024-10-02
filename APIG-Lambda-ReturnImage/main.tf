# Variables
variable "lambda_fn_name" {
    default = "demo-fn-RetrieveImage"
    type = string
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.69.0"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region = "us-east-1"
}


data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

data "archive_file" "lambda-zip-RetrieveImage" {
  type        = "zip"
  source_dir  = "${path.module}/Lambda-RetrieveImage"
  output_path = "lambda_function_payload.zip"
}

data "aws_iam_policy_document" "lambda_logging" {
  statement {
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = ["arn:aws:logs:*:*:*"]
  }
}


resource "aws_iam_role" "cus_role_lambda_retrieveImg" {
  name               = "cus_role_lambda_retrieveImg"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

resource "aws_cloudwatch_log_group" "cw-lambda" {
  name              = "/aws/lambda/${var.lambda_fn_name}"
  retention_in_days = 14
}

resource "aws_iam_policy" "lambda_logging" {
  name        = "lambda_logging"
  path        = "/"
  description = "IAM policy for logging from a lambda"
  policy      = data.aws_iam_policy_document.lambda_logging.json
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.cus_role_lambda_retrieveImg.name
  policy_arn = aws_iam_policy.lambda_logging.arn
}

### LAMBDA
resource "aws_lambda_function" "demo-fn-RetrieveImage" {
  filename      = "lambda_function_payload.zip"
  function_name = var.lambda_fn_name
  role          = aws_iam_role.cus_role_lambda_retrieveImg.arn
  handler       = "handler.lambda_handler"
  source_code_hash = data.archive_file.lambda-zip-RetrieveImage.output_base64sha256
  runtime = "nodejs20.x"
  depends_on = [
    aws_iam_role_policy_attachment.lambda_logs,
    aws_cloudwatch_log_group.cw-lambda,
  ]
}


### APIG

resource "aws_api_gateway_rest_api" "demo-rest-retrieveImg" {
  #binary_media_types = ["image/jpeg","image/png","image/jpg","image/bmp"]
  binary_media_types = ["image/png"]
  body = jsonencode({
    openapi = "3.0.1"
    info = {
      title   = "demo-rest-lambda-retrieveImg"
      version = "1.0"
    }
    paths = {
      "/getImg" = {
        get = {
          x-amazon-apigateway-integration = {
            httpMethod  = "POST"
            payloadFormatVersion = "1.0"
            type = "AWS_PROXY"
            uri = aws_lambda_function.demo-fn-RetrieveImage.invoke_arn
          }
        }
      }
    }
  })
  name = "demo-rest-lambda-retrieveImg"
  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_deployment" "demo-rest-retrieveImg-deployment" {
  rest_api_id = aws_api_gateway_rest_api.demo-rest-retrieveImg.id

  triggers = {
    redeployment = sha1(jsonencode([
        aws_api_gateway_rest_api.demo-rest-retrieveImg.body,
        ]))
  }

  depends_on = [ aws_api_gateway_rest_api.demo-rest-retrieveImg ]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "demo-rest-retrieveImg-stage" {
  deployment_id = aws_api_gateway_deployment.demo-rest-retrieveImg-deployment.id
  rest_api_id   = aws_api_gateway_rest_api.demo-rest-retrieveImg.id
  stage_name    = "prod"
}

resource "aws_lambda_permission" "apig_create_permission" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.demo-fn-RetrieveImage.function_name
  principal     = "apigateway.amazonaws.com"
  
  source_arn = "${aws_api_gateway_rest_api.demo-rest-retrieveImg.execution_arn}/*/*/*"
}

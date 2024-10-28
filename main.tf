provider "aws" {
  region = "us-east-1"
  default_tags {
    tags = {
      Environment = "Test"
      Owner       = "sleroy"
      Project     = "WorkloadA"
    }
  }
}


resource "aws_iam_role" "lambda_role" {
  name = "SqlQueryMonitor_Lambda_Function_Role"
  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Action" : "sts:AssumeRole",
        "Principal" : {
          "Service" : "lambda.amazonaws.com"
        },
        "Effect" : "Allow",
        "Sid" : ""
      }
    ]
  })
}

resource "aws_iam_policy" "iam_policy_for_lambda" {
  name        = "aws_iam_policy_for_terraform_aws_lambda_role"
  path        = "/"
  description = "AWS IAM Policy for managing aws lambda role"
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Action" : [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        "Resource" : "arn:aws:logs:*:*:*",
        "Effect" : "Allow"
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ],
        "Resource" : var.db_secret_id
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach_iam_policy_to_iam_role" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.iam_policy_for_lambda.arn
}

data "archive_file" "zip_the_python_code" {
  type        = "zip"
  source_dir  = "${path.module}/python/"
  output_path = "${path.module}/python/sqlmonitor-python.zip"
}

resource "aws_lambda_function" "terraform_lambda_func" {
  filename      = "${path.module}/python/sqlmonitor-python.zip"
  function_name = "SqlQueryMonitor_Lambda_Function"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.lambda_handler"
  runtime       = "python3.12"
  depends_on    = [aws_iam_role_policy_attachment.attach_iam_policy_to_iam_role]
}

resource "aws_scheduler_schedule" "scheduler_rule" {
  name       = "sqlquery-monitor-schedule"
  group_name = "default"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression = "rate(1 minute)"

  target {
    arn      = aws_lambda_function.terraform_lambda_func.arn
    role_arn = aws_iam_role.eventbridge_scheduler_role.arn
  }
}


resource "aws_iam_role" "eventbridge_scheduler_role" {
  name = "SqlQueryMonitorLambaExecutionRole"
  assume_role_policy = jsonencode(
    {
      "Version" : "2012-10-17",
      "Statement" : [
        {
          "Effect" : "Allow",
          "Principal" : {
            "Service" : "scheduler.amazonaws.com"
          },
          "Action" : "sts:AssumeRole"
        }
      ]
  })
}


resource "aws_iam_policy" "iam_policy_run_sqlquery_lambda" {
  name        = "iam_policy_run_sqlquery_lambda"
  path        = "/"
  description = "AWS IAM Policy to execute lambda from EventBridge scheduler"
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Action" : [
          "lambda:InvokeFunction"
        ],
        "Effect" : "Allow",
        "Resource" : aws_lambda_function.terraform_lambda_func.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach_eventbridge_policy_to_eventbridge_role" {
  role       = aws_iam_role.eventbridge_scheduler_role.name
  policy_arn = aws_iam_policy.iam_policy_run_sqlquery_lambda.arn
}

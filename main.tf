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

# Prepare Lambda package (https://github.com/hashicorp/terraform/issues/8344#issuecomment-345807204)
resource "null_resource" "pip" {
  triggers = {
    main         = "${base64sha256(file("python/index.py"))}"
    requirements = "${base64sha256(file("python/requirements.txt"))}"
  }

  provisioner "local-exec" {
    command = "${var.pip_path} install -r ${path.root}/python/requirements.txt -t python/lib"
  }
}

data "archive_file" "zip_the_python_code" {
  type        = "zip"
  source_dir  = "${path.module}/python/"
  #source_file = "${path.module}/python/index.py"
  output_path = "${path.module}/temp/sqlmonitor-python.zip"
  depends_on = [null_resource.pip]
}



resource "aws_lambda_function" "terraform_lambda_func" {  
  filename      = data.archive_file.zip_the_python_code.output_path
  function_name = "SqlQueryMonitor_Lambda_Function"
  role          = aws_iam_role.lambda_role.arn
  timeout       = 120
  handler       = "index.lambda_handler"
  runtime       = "python3.12"
  depends_on    = [aws_iam_role_policy_attachment.attach_iam_policy_to_iam_role, aws_cloudwatch_log_group.lambda_logging]
  memory_size   = 256
  source_code_hash = data.archive_file.zip_the_python_code.output_base64sha256
    # if you want to specify the retention period of the logs you need this
}


# This defines the IAM policy needed for a lambda to log. #1
data "aws_iam_policy_document" "lambda_logging" {
  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = [
      "arn:aws:logs:*:*:*",
    ]
  }
}

resource "aws_iam_policy" "lambda_logging" {
  name   = "sqlquery-monitor-lambda-logging"
  path   = "/"
  policy = "${data.aws_iam_policy_document.lambda_logging.json}"
}

resource "aws_iam_role_policy_attachment" "lambda_logging" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "${aws_iam_policy.lambda_logging.arn}"
}

resource "aws_cloudwatch_log_group" "lambda_logging" {
  name              = "/aws/lambda/sqlquery-monitor-lambda-function"
  retention_in_days = 5
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

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

/* VPC Resources*/
data "aws_vpc" "vpc" {
  filter {
    name   = "tag:Name"
    values = [var.vpc_name]
  }
}

data "aws_subnets" "private_db_subnet" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.vpc.id]
  }

  filter {
    name   = "tag:Name"
    values = var.subnets
  }
}

resource "aws_security_group" "lambda_security_group" {
  name        = "lambda_security_group"
  description = "Allow Sqlserver inbound traffic and all outbound traffic"
  vpc_id      = data.aws_vpc.vpc.id

  tags = {
    Name = "lambda_security_group"
  }
}

resource "aws_vpc_security_group_ingress_rule" "allow_sqlserver_ipv4" {
  security_group_id = aws_security_group.lambda_security_group.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 1443
  ip_protocol       = "tcp"
  to_port           = 1443
}

resource "aws_vpc_security_group_ingress_rule" "allow_sqlserver2_ipv4" {
  security_group_id = aws_security_group.lambda_security_group.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 1433
  ip_protocol       = "tcp"
  to_port           = 1434
}

resource "aws_vpc_security_group_ingress_rule" "allow_sqlserver3_ipv4" {
  security_group_id = aws_security_group.lambda_security_group.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 4032
  ip_protocol       = "tcp"
  to_port           = 4032
}

resource "aws_vpc_security_group_ingress_rule" "allow_sqlserver4_ipv4" {
  security_group_id = aws_security_group.lambda_security_group.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 1434
  ip_protocol       = "tcp"
  to_port           = 1434
}

resource "aws_vpc_security_group_ingress_rule" "allow_sqlserver5_ipv4" {
  security_group_id = aws_security_group.lambda_security_group.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 1434
  ip_protocol       = "udp"
  to_port           = 1434
}

resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4" {
  security_group_id = aws_security_group.lambda_security_group.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}

/* Security */

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
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "cloudwatch:PutMetricData",
        ],
        "Resource" : "*"
      },
      {
        "Sid" : "VisualEditor0",
        "Effect" : "Allow",
        "Action" : [
          "ec2:CreateNetworkInterface",
          "ec2:CreateTags",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface",
          "ec2:AssignPrivateIpAddresses",
          "ec2:UnassignPrivateIpAddresses"
        ],
        "Resource" : "*"
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ],
        "Resource" : [
          "arn:aws:logs:*:*:*",
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach_iam_policy_to_iam_role" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.iam_policy_for_lambda.arn
}

/* Packaging */

# Prepare Lambda package (https://github.com/hashicorp/terraform/issues/8344#issuecomment-345807204)
resource "null_resource" "pip" {
  triggers = {
    main         = "${base64sha256(file("lambdas/sqlserver/index.mjs"))}"
    requirements = "${base64sha256(file("lambdas/sqlserver/package.json"))}"
  }

  provisioner "local-exec" {
    command = "bash ${path.module}/packaging.sh"
  }
}

data "archive_file" "zip_the_python_code" {
  type       = "zip"
  source_dir = "${path.module}/lambda_dist_pkg/"
  #source_file = "${path.module}/python/index.py"
  output_path = "${path.module}/temp/sqlmonitor-sqlsqerver.zip"
  depends_on  = [null_resource.pip]
}



resource "aws_lambda_function" "terraform_lambda_func" {
  filename         = data.archive_file.zip_the_python_code.output_path
  function_name    = "SqlQueryMonitor_Lambda_Function"
  role             = aws_iam_role.lambda_role.arn
  timeout          = 120
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  depends_on       = [aws_iam_role_policy_attachment.attach_iam_policy_to_iam_role, aws_cloudwatch_log_group.lambda_logging]
  memory_size      = 256
  source_code_hash = data.archive_file.zip_the_python_code.output_base64sha256
  vpc_config {
    subnet_ids         = data.aws_subnets.private_db_subnet.ids
    security_group_ids = [aws_security_group.lambda_security_group.id]
  }
}

/** Loggin */

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

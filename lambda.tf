resource "aws_iam_role_policy" "dns_refresh" {
    name = "dns_refresh_policy"
    role = "${aws_iam_role.dns_refresh.id}"
    policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "EC2Things",
            "Action": [
                "ec2:DescribeInstances"
            ],
            "Effect": "Allow",
            "Resource": "*"
        },
        {
            "Sid": "Route53Things",
            "Action": [
                "route53:ListHostedZonesByName",
                "route53:ListResourceRecordSets",
                "route53:ChangeResourceRecordSets"
            ],
            "Effect": "Allow",
            "Resource": "*"
        },
        {
	    "Sid" : "LogThings",
	    "Effect": "Allow",
            "Action": [
              "logs:CreateLogGroup",
              "logs:CreateLogStream",
              "logs:PutLogEvents",
              "logs:DescribeLogStreams"
            ],
            "Resource": [
              "*"
            ]
        } 
    ]
}
EOF
}

resource "aws_iam_role" "dns_refresh" {
    name = "dns_refresh"
        assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_lambda_function" "dns_refresh" {
    filename = "lambda/dns_refresh.zip"
    function_name = "dns_refresh"
    role = "${aws_iam_role.dns_refresh.arn}"
    handler = "dns_refresh.lambda_handler"
    source_code_hash = "${base64sha256(file("lambda/dns_refresh.zip"))}"
    runtime = "python2.7"
    timeout = 30
    environment {
        variables = {
            TAG_NAME_PREFIX = "ELKv5-${lookup(var.env_shortname, var.environment)}"
	    ZONE_NAME = "${lookup(var.local_dns_name, var.environment)}"
            PRIVATE_ZONE = "True"
	    TTL = "60"
        }
    }
}




resource "aws_cloudwatch_event_rule" "dns_refresh" {
  name = "dns_refresh_schedule"
  description = "Schedule frequency for Lambda-based DNS refresh"
  schedule_expression = "rate(1 minute)"
}





resource "aws_cloudwatch_event_target" "dns_refresh" {
  rule = "${aws_cloudwatch_event_rule.dns_refresh.name}"
  target_id = "dns_refresh"
  arn = "${aws_lambda_function.dns_refresh.arn}"
}

data "template_file" "lambda_vpc_flow_policy" {
    template = "${file("templates/lambda_vpc_flow_policy.tpl")}"

    vars {
        account_id = "${lookup(var.aws_account_ids, var.environment)}"
        region = "${var.aws_region}"
        stream_name = "${aws_kinesis_stream.elk-flow-logs.name}"
    }
}

resource "aws_iam_role_policy" "lambda_vpc_flow" {
    name = "lambda_vpc_flow_policy"
    role = "${aws_iam_role.lambda_vpc_flow.id}"
    policy = "${data.template_file.lambda_vpc_flow_policy.rendered}"
}

resource "aws_iam_role" "lambda_vpc_flow" {
    name = "lambda_vpc_flow"
        assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_lambda_function" "lambda_vpc_flow" {
    filename = "lambda/vpc_flow.zip"
    function_name = "vpc_flow"
    role = "${aws_iam_role.lambda_vpc_flow.arn}"
    handler = "vpc_flow.lambda_handler"
    source_code_hash = "${base64sha256(file("lambda/vpc_flow.zip"))}"
    runtime = "python2.7"
    timeout = 30
    environment {
        variables = {
            KINESIS_STREAM = "elk-broker"
            KINESIS_PARTITION = "main"
        }
    }
}

resource "aws_lambda_event_source_mapping" "lambda_vpc_flow" {
    batch_size = 100
    event_source_arn = "${aws_kinesis_stream.elk-flow-logs.arn}"
    enabled = true
    function_name = "${aws_lambda_function.lambda_vpc_flow.arn}"
    starting_position = "TRIM_HORIZON"
}
aws_cloudwatch_event_rule

"${aws_cloudwatch_event_rule.shutdown_rule.arn}"
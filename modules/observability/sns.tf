resource "aws_sns_topic" "alarms" {
  name = "${var.name_prefix}-alarms-${var.environment}"
  tags = var.tags
}

resource "aws_sns_topic_subscription" "alarm_email" {
  for_each = toset(var.alarm_emails)

  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = each.value
}

# critical_deletion_alarms.tf의 EventBridge 규칙이 이 토픽에 publish할 수 있어야 한다.
resource "aws_sns_topic_policy" "allow_eventbridge" {
  arn = aws_sns_topic.alarms.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowEventBridgePublish"
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "SNS:Publish"
      Resource  = aws_sns_topic.alarms.arn
    }]
  })
}

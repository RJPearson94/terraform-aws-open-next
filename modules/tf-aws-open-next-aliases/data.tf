data "aws_ssm_parameter" "origin_aliases" {
  name = aws_ssm_parameter.origin_aliases.name
}

fmt:
	@echo "==> Format Terraform Code"
	terraform fmt -recursive

test:
	@echo "==> Test Terraform Code"
	terraform -chdir=modules/tf-aws-open-next-zone init -backend=false -input=false
	terraform -chdir=modules/tf-aws-open-next-zone test

.PHONY: fmt test

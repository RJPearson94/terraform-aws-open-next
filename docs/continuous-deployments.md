# Continuous deployment

For this functionality to work correctly, lifecycle rules have been added to the production distribution to ignore changes to origins, ordered_cache_behaviors, default_cache_behavior and custom_error_responses. For Terraform to be able to update the distribution, you will need to update the staging distribution and then promote the changes.

## Initial deployment

AWS doesn't allow you to attach the continuous deployment policy to the production distribution on the first deployment. Therefore, you will need to set the deployment to `NONE`. To configure this, please add the following configuration.

```tf
continuous_deployment = {
  use = true
  deployment = "NONE"
}
```

## Use staging distribution

When you want to create/ use the staging distribution, there are two options for shifting traffic to the staging distribution header or by weight (up to 15% at the time of writing). To configure this, please add the following configuration.

```tf
continuous_deployment = {
  use = true
  deployment = "ACTIVE"
  traffic_config = {
    header = {
      name = "aws-cf-cd-staging" # Update the header name with a value of your choice. Currently, AWS enforce the header starts with `aws-cf-cd`
      value = "true" # Update the header value with a value of your choice.
    }
  }
}
```

or 

```tf
continuous_deployment = {
  use = true
  deployment = "ACTIVE"
  traffic_config = {
    weight = {
        percentage = "0.10" 
    }
  }
}
```

For weighted deployments, you can also configure session stickiness. See the documentation below for more information.

*Note:* You can update the staging distribution multiple times before promoting the changes.

## Promotion

Please add the following configuration to promote the staging distribution.

```tf
continuous_deployment = {
  use = true
  deployment = "PROMOTE"
  traffic_config = {
    weight = {
        percentage = "0.10" 
    }
  }
}
```

## Detach staging distribution

You must remove the continuous deployment policy from the production distribution to remove the staging distribution. To do this, you must set the deployment to `DETACH`. Please add the following configuration.

```tf
continuous_deployment = {
  use = true
  deployment = "DETACH"
  traffic_config = {
    weight = {
        percentage = "0.10" 
    }
  }
}
```

*Note:* you can detach the staging distribution without promoting the changes to the production distribution. This will remove the continuous deployment policy, shifting 100% of traffic back to the production distribution.

## Remove staging distribution

Please add the following configuration to remove the staging distribution.

```tf
continuous_deployment = {
  use = true
  deployment = "NONE"
}
```

*Note:* Please detach the staging distribution before removing it, otherwise Terraform may fail if the production distribution is retained.


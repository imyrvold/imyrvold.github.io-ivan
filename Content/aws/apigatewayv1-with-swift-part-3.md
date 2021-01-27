---
date: 2021-01-28 12:00
description: Using APIGateway (version 1) with Swift Lambda - Part 3
tags: lambda, localstack, apigateway, aws, docker, swift
---
###### Published 2021-01-28
# Using Amazon API Gateway (Rest API) with Swift Lambda - Part 3

This is the last part in my blog posts about API Gateway and Lambda integration. The [first part](/aws/apigatewayv1-with-swift-part-1) showed how we could integrate with `GET` query parameters, the [second part](/aws/apigatewayv1-with-swift-part-2) showed the integration with `POST` method. This blog post will continue with integration with `GET` path parameters.

You can find the complete code of all 3 integrations in my [GitHub repository](https://github.com/imyrvold/lambda_calc3).

## Integration 3: Create a GET method with path parameters

Rename the `19 apigateway create-deployment...` in `scripts/setup_aws.sh` script to `26 apigateway create-deployment...` We will add the commands in the shell scripts between step 18 and step 26.

Add the first command in integration 3 to the shell script between step 18 and step 26:

```
# Integration 3
# Resources /{operand1}/{operand2}/{operator} GET

echo "19 apigateway create-resource..."
aws apigateway create-resource \
    --region ${REGION} \
    --rest-api-id ${API_ID} \
    --parent-id ${RESOURCE_ID} \
    --path-part {operand1} \
    > results/aws/create-resource-operand1.json

[ $? == 0 ] || fail 19 "Failed: AWS / apigateway / create-resource"

RESOURCE_OPERAND1_PATH="$RESOURCE_NAME/{operand1}"
RESOURCE_OPERAND1_ID=$(aws apigateway get-resources --rest-api-id ${API_ID} --query "items[?path==\`/$RESOURCE_OPERAND1_PATH\`].id" --output text --region ${REGION})
```

We add a new resource, which contains the path of `operand1`. That means that the endpoint will contain the `calc` resource we created in [step 6](/aws/apigatewayv1-with-swift-part-1/#step6) of the first blog post plus the `operand1` path part. 
We save the new path in `RESOURCE_OPERAND1_PATH` and the id of the new resource in `RESOURCE_OPERAND1_ID`, because they will be used in the next command.

We need a new resource for the second parameter:

```
echo "20 apigateway create-resource..."
aws apigateway create-resource \
    --region ${REGION} \
    --rest-api-id ${API_ID} \
    --parent-id ${RESOURCE_OPERAND1_ID} \
    --path-part {operand2} \
    > results/aws/create-resource-operand2.json

[ $? == 0 ] || fail 20 "Failed: AWS / apigateway / create-resource"

RESOURCE_OPERAND2_PATH="$RESOURCE_OPERAND1_PATH/{operand2}"
RESOURCE_OPERAND2_ID=$(aws apigateway get-resources --rest-api-id ${API_ID} --query "items[?path==\`/$RESOURCE_OPERAND2_PATH\`].id" --output text --region ${REGION})
```

We have added a new path part in `RESOURCE_OPERAND2_PATH` and the new id for this resource in `RESOURCE_OPERAND2_PATH`, which will be used in the next command.

We also create a new resource for the operator:

```
echo "21 apigateway create-resource..."
aws apigateway create-resource \
    --region ${REGION} \
    --rest-api-id ${API_ID} \
    --parent-id ${RESOURCE_OPERAND2_ID} \
    --path-part {operator} \
    > results/aws/create-resource-operator.json

[ $? == 0 ] || fail 21 "Failed: AWS / apigateway / create-resource"

RESOURCE_OPERATOR_PATH="$RESOURCE_OPERAND2_PATH/{operator}"
RESOURCE_OPERATOR_ID=$(aws apigateway get-resources --rest-api-id ${API_ID} --query "items[?path==\`/$RESOURCE_OPERATOR_PATH\`].id" --output text --region ${REGION})
```

We can now add the `GET` method to the operator resource:

```
echo "22 apigateway put-method..."
aws apigateway put-method \
    --region ${REGION} \
    --rest-api-id ${API_ID} \
    --resource-id ${RESOURCE_OPERATOR_ID} \
    --http-method GET \
    --authorization-type NONE \
    --request-parameters "method.request.path.operand1=true,method.request.path.operand2=true,method.request.path.operator=true" \
    > results/aws/put-get-path-method.json

[ $? == 0 ] || fail 22 "Failed: AWS / apigateway / put-method"
```
We add the request parameters for `operand1` and `operand2` and `operator`.

Next we create the method response for the `GET` method, with statuscode 200:

```
echo "23 apigateway put-method-response..."
aws apigateway put-method-response \
    --region ${REGION} \
    --rest-api-id ${API_ID} \
    --resource-id ${RESOURCE_OPERATOR_ID} \
    --http-method GET \
    --status-code 200 \
    --response-models application/json=Empty \
    > results/aws/put-method-response2.json

[ $? == 0 ] || fail 23 "Failed: AWS / apigateway / put-method-response"
```

Before we add the integration, we need to add the `request-templates2.json` JSON file:

```
{
  "application/json":"{\n   \"a\": $input.params('operand1'),\n   \"b\": $input.params('operand2'),\n   \"op\": #if($input.params('operator')=='%2F')\"/\"#{else}\"$input.params('operator')\"#end\n   \n}"
}

```
This template maps the three URL path parameters into designated property values in the JSON object.
We continue with adding the integration to the `GET` method with path parameters:

```
echo "24 apigateway put-integration..."
aws apigateway put-integration \
    --region ${REGION} \
    --rest-api-id ${API_ID} \
    --resource-id ${RESOURCE_OPERATOR_ID} \
    --http-method GET \
    --type AWS \
    --integration-http-method POST \
    --uri arn:aws:apigateway:${REGION}:lambda:path/2015-03-31/functions/${LAMBDA_ARN}/invocations \
    --credentials ${ROLE_ARN} \
    --content-handling CONVERT_TO_TEXT \
    --passthrough-behavior WHEN_NO_TEMPLATES \
    --request-templates file://request-templates2.json \
    > results/aws/put-get-integration2.json

[ $? == 0 ] || fail 24 "Failed: AWS / apigateway / put-integration"
```

The last command is the integration response:

```
echo "25 apigateway put-integration-response..."
aws apigateway put-integration-response \
    --region ${REGION} \
    --rest-api-id ${API_ID} \
    --resource-id ${RESOURCE_OPERATOR_ID} \
    --http-method GET \
    --status-code 200 \
    --response-templates application/json="" \
    > results/aws/put-get-integration-response2.json

[ $? == 0 ] || fail 25 "Failed: AWS / apigateway / put-integration-response"
```

We have now completed all three integrations, and we just need to add the integration 3 testing commands at the end of the file:

```
echo
echo
echo "Integration 3"
echo "Testing GET with path parameters:"
echo "5 * 8"
cat << EOF
curl -i --request GET \
https://${API_ID}.execute-api.eu-west-1.amazonaws.com/${STAGE}/calc/5/8/\mul
EOF
echo

curl -i --request GET \
https://${API_ID}.execute-api.eu-west-1.amazonaws.com/${STAGE}/calc/5/8/\mul
```

## Deploy Lambda function with API Gateway

Starting the script with `scripts/setup_aws.sh` will now give a result like this:
![Integration 3 result](/images/lambda/integration3_result.png)

If you test the new integration with Safari, it should look like this:
![Integration3 with Safari](/images/lambda/integration3_safari.png)

## Conclusion

The three blog posts have showed how we can make use of API Gateway's integrations to call a Lambda Swift function with

* GET method with query parameters
* POST method with body parameters
* GET method with path parameters

\
Log into your API Gateway console, to see how the final integrations looks like:

![API Gateway console](/images/lambda/integrations_aws_console.png)

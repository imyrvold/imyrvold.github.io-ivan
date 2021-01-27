---
date: 2021-01-27 12:00
description: Using APIGateway (version 1) with Swift Lambda - Part 2
tags: lambda, localstack, apigateway, aws, docker, swift
---
###### Published 2021-01-27
# Using Amazon API Gateway (Rest API) with Swift Lambda - Part 2

[The first part](/aws/apigatewayv1-with-swift-part-1) of this three-part blog post series showed how we can integrate API Gateway with our Swift Lambda function. This blog post will continue with the `setup_aws.sh` script to add a POST integration.

You can clone the code from [my GitHub repository](https://github.com/imyrvold/lambda_calc2) for the Swift Lambda function and scripts.

## Integration 2: Create a POST method with a JSON payload

Rename the `12 apigateway create-deployment..` to `19 apigateway create-deployment..` We will add the next commands between step 11 and 19.

Add the following command to the `setup_aws.sh` following step 11 (but before step 19):

```
echo "12 apigateway create-model..."
aws apigateway create-model \
    --rest-api-id ${API_ID} \
    --name ${INPUT_MODEL_NAME} \
    --content-type application/json \
    --schema "{\"type\": \"object\", \"properties\": { \"a\" : { \"type\": \"number\" },  \"b\" : { \"type\": \"number\" }, \"op\" : { \"type\": \"string\" }}, \"title\": \"${INPUT_MODEL_NAME}\"}" \
    > results/aws/create-input-model.json

[ $? == 0 ] || fail 12 "Failed: AWS / apigateway / create-model"
```
We are creating an input model which is used by API Gateway to validate the incoming request body. The `schema` describes the input as two numbers, `a` and `b` and the operation `op` which is a string.

We also needs an output model which describes the data structure of the calculated output from the Lambda function. It can be used to map the integration response data to a different model. It is not used in the tutorial here, but I include it for completeness. The [AWS tutorial](https://docs.aws.amazon.com/apigateway/latest/developerguide/integrating-api-with-aws-services-lambda.html) is adding it in the tutorial in **Integration 2** step 9, so we do it as well:

```
echo "13 apigateway create-model..."
aws apigateway create-model \
    --rest-api-id ${API_ID} \
    --name ${OUTPUT_MODEL_NAME} \
    --content-type application/json \
    --schema "{ \"type\": \"object\", \"properties\": { \"c\" : { \"type\": \"number\"}}, \"title\":\"${OUTPUT_MODEL_NAME}\"}" \
    > results/aws/create-output-model.json

[ $? == 0 ] || fail 13 "Failed: AWS / apigateway / create-model"
```
The same with the results model. It describes the data structure of the returned response data. It references both the Input and Output schemas, but we don't use it in the tutorial:

```
echo "14 apigateway create-model..."
aws apigateway create-model \
    --rest-api-id ${API_ID} \
    --name ${RESULT_MODEL_NAME} \
    --content-type application/json \
    --schema "{ \"type\": \"object\", \"properties\": { \"input\":{ \"\$ref\": \"https://apigateway.amazonaws.com/restapis/${API_ID}/models/${INPUT_MODEL_NAME}\"}, \"output\":{\"\$ref\": \"https://apigateway.amazonaws.com/restapis/${API_ID}/models/Output\"}}, \"title\": \"${OUTPUT_MODEL_NAME}\"}" \
    > results/aws/create-result-model.json
 
 [ $? == 0 ] || fail 14 "Failed: AWS / apigateway / create-model"
```

We can now create the `POST` http method:

```
echo "15 apigateway put-method..."
aws apigateway put-method \
    --region ${REGION} \
    --rest-api-id ${API_ID} \
    --resource-id ${RESOURCE_ID} \
    --http-method POST \
    --authorization-type NONE \
    > results/aws/put-post-method.json

[ $? == 0 ] || fail 15 "Failed: AWS / apigateway / put-method"
```

Note that we use `RESOURCE_ID` which is the `calc` resource we created in step 6 in the [first post](/aws/apigatewayv1-with-swift-part-1/#step6) of this three-part post series. This means that the endpoint of the POST method will also end in `calc`.

Next we create the method response for the `POST` method, which will be 200 if everything went ok:

```
echo "16 apigateway put-method-response..."
aws apigateway put-method-response \
    --region ${REGION} \
    --rest-api-id ${API_ID} \
    --resource-id ${RESOURCE_ID} \
    --http-method POST \
    --status-code 200 \
    --response-models application/json=Empty \
    > results/aws/put-method-response.json

[ $? == 0 ] || fail 16 "Failed: AWS / apigateway / put-method"
```

Now we are ready to create the integration for the `POST` http method. Note that we use the `AWS` type, the same as we did in the previous blog post:

```
echo "17 apigateway put-integration..."
aws apigateway put-integration \
    --region ${REGION} \
    --rest-api-id ${API_ID} \
    --resource-id ${RESOURCE_ID} \
    --http-method POST \
    --type AWS \
    --integration-http-method POST \
    --uri arn:aws:apigateway:${REGION}:lambda:path/2015-03-31/functions/${LAMBDA_ARN}/invocations \
    --credentials ${ROLE_ARN} \
    --passthrough-behavior WHEN_NO_MATCH \
    > results/aws/put-post-integration.json

[ $? == 0 ] || fail 17 "Failed: AWS / apigateway / put-integration"
```

And to complete the `POST` integration, we create the integration response. If we wanted, we could map the response from the Lambda function to another JSON, but in this case we just return the JSON that the Swift Lambda function returns:

```
echo "18 apigateway put-integration-response..."
aws apigateway put-integration-response \
    --region ${REGION} \
    --rest-api-id ${API_ID} \
    --resource-id ${RESOURCE_ID} \
    --http-method POST \
    --status-code 200 \
    --response-templates application/json="" \
    > results/aws/put-post-integration-response.json

[ $? == 0 ] || fail 18 "Failed: AWS / apigateway / put-integration-response"
```

Add the command to test the `POST` endpoint at the end of the file:

```
echo
echo
echo "Integration 2"
echo "Testing POST:"
echo "8 + 6"
cat << EOF
curl -i --request POST \
--header "Content-Type: application/json" \
--data '{"a": 8, "b": 6, "op": "add"}' \
https://${API_ID}.execute-api.eu-west-1.amazonaws.com/${STAGE}/calc
EOF
echo

curl -i --request POST \
--header "Content-Type: application/json" \
--data '{"a": 8, "b": 6, "op": "add"}' \
https://${API_ID}.execute-api.eu-west-1.amazonaws.com/${STAGE}/calc
```

## Deploy Lambda function with API Gateway
We have now endpoints for both a `GET` http method with query parameters, and a `POST` http method with parameters in the http body. Both should produce the same result.

Start the setup script with the command `scripts/setup_aws.sh`, and we should now at the end have a result like this:

![Integration 2 result](/images/lambda/integration2_result.png)

The last blog post in this three-part series will show how we can integrate with a `GET` method that uses path parameters.


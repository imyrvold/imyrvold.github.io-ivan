---
date: 2021-04-25 09:34
description: Rekognition Lambda Function with Swift Part 3
tags: lambda, aws, docker, swift, apigateway
---
###### Published 2021-04-25
# Rekognition Lambda Function with Swift Part 3

In the two previous blog posts, [part1](aws/rekognition-lambda-part-1) and [part2](aws/rekognition-lambda-part-2) we created two Lambda functions with Swift.  In this episode I will show how to connect the Lambda function serviceFunction to the AWS API Gateway (Rest API). We will not do any changes to the Swift code, so the only changes will be in the CDK infrastructure code.

## Amazon API Gateway with AWS Lambda Integration

Before we import the API Gateway into our CDK infrastructure code, we need to install the CDK construct:

`npm install @aws-cdk/aws-apigateway`

We can now import the apigateway constructs in `lib/devhr-project-stack.ts`:

```
import * as cdk from '@aws-cdk/core'
import * as s3 from '@aws-cdk/aws-s3'
import * as lambda from '@aws-cdk/aws-lambda'
import * as dynamodb from '@aws-cdk/aws-dynamodb'
import { Duration } from '@aws-cdk/core'
import * as iam from '@aws-cdk/aws-iam'
import * as event_sources from '@aws-cdk/aws-lambda-event-sources'
import * as apigw from '@aws-cdk/aws-apigateway'
import { PassthroughBehavior } from '@aws-cdk/aws-apigateway'
```

At the end of the file, add a new API Gateway for Lambda Rest API:

```
const api = new apigw.LambdaRestApi(this, 'imageAPI', {
  defaultCorsPreflightOptions: {
    allowOrigins: apigw.Cors.ALL_ORIGINS,
    allowMethods: apigw.Cors.ALL_METHODS
  },
  handler: serviceFn,
  proxy: false
})
```

We want to use query parameters in the API GET call to the API Gateway for the serviceFunction Lambda function, so we have to add that as an integration to the API Gateway. The query parameters are `action` for the action to perform in the Lambda function, and `key` for the photo name:

```
// =====================================================================================
// This construct builds a new Amazon API Gateway with AWS Lambda Integration
// =====================================================================================
const lambdaIntegration = new apigw.LambdaIntegration(serviceFn, {
  proxy: false,
  requestParameters: {
    'integration.request.querystring.action': 'method.request.querystring.action',
    'integration.request.querystring.key': 'method.request.querystring.key'
  },
  requestTemplates: {
    'application/json': JSON.stringify({ action: "$util.escapeJavaScript($input.params('action'))", key: "$util.escapeJavaScript($input.params('key'))" })
  },
  passthroughBehavior: PassthroughBehavior.WHEN_NO_TEMPLATES,
  integrationResponses: [
    {
      statusCode: "200",
      responseParameters: {
        // We can map response parameters
        // - Destination parameters (the key) are the response parameters (used in mappings)
        // - Source parameters (the value) are the integration response parameters or expressions
        'method.response.header.Access-Control-Allow-Origin': "'*'"
      }
    },
    {
      // For errors, we check if the error message is not empty, get the error data
      selectionPattern: "(\n|.)+",
      statusCode: "500",
      responseParameters: {
        'method.response.header.Access-Control-Allow-Origin': "'*'"
      }
    }
  ],
})
```

The first method we add to the API Gateway integration is the `GET` method to get the labels from the DynamoDB database:

```
    // =====================================================================================
    // API Gateway
    // =====================================================================================
    const imageAPI = api.root.addResource('images')
​
    // GET /images
    imageAPI.addMethod('GET', lambdaIntegration, {
      requestParameters: {
        'method.request.querystring.action': true,
        'method.request.querystring.key': true
      },
      methodResponses: [
        {
          statusCode: "200",
          responseParameters: {
            'method.response.header.Access-Control-Allow-Origin': true,
          },
        },
        {
          statusCode: "500",
          responseParameters: {
            'method.response.header.Access-Control-Allow-Origin': true,
          },
        }
      ]
    })
```

We also need a `DELETE` method to delete the photo from the AWS S3 buckets and the DynamoDB database:

```
    // DELETE /images
    imageAPI.addMethod('DELETE', lambdaIntegration, {
      requestParameters: {
        'method.request.querystring.action': true,
        'method.request.querystring.key': true
      },
      methodResponses: [
        {
          statusCode: "200",
          responseParameters: {
            'method.response.header.Access-Control-Allow-Origin': true,
          },
        },
        {
          statusCode: "500",
          responseParameters: {
            'method.response.header.Access-Control-Allow-Origin': true,
          },
        }
      ]
    })
  }
}
```

The only thing we need to change in the `devhr-project-cicd-infra.ts` file is the branch from part2 to part3 in the pipeline sourceAction:

```
sourceAction: new codepipeline_actions.GitHubSourceAction({
    actionName: 'DownloadSources',
    owner: 'imyrvold',
    repo: 'DevhrProjectCICD',
    branch: 'part3',
        oauthToken: cdk.SecretValue.secretsManager('github-token'),
        output: sourceArtifact
}),
```

## Test ServiceFunction getLabels with API Gateway

With Terminal, we can now bootstrap the infrastructure code:

`cdk bootstrap \`
`--cloudformation-execution-policies arn:aws:iam::aws:policy/AdministratorAccess \`
`aws://<your AWS Account ID>/eu-west-1`  


and deploy it: `cdk deploy`

When the pipeline have built the Lambda function, we can test it with a photo.
First, list all your S3 buckets with the command:
`aws s3 ls`

You should get the two lambda image buckets in the result. I got this back:

`2021-04-25 09:13:31 lambdadeploymentstage-de-cdkreknimagebucketa588dc-1123ayav2rc42`
`2021-04-25 09:11:48 lambdadeploymentstage-de-cdkreknimagebucketresize-12azqz1h8qxs5`

in addition to the ci/cd s3 bucket.

Copy a photo of your choice to the first image bucket (the one which doesn't have resize in it's name):

`aws s3 cp ~/Pictures/IMG_3080.jpeg s3://lambdadeploymentstage-de-cdkreknimagebucketa588dc-1123ayav2rc42`

Open the AWS API Gateway console in your browser, and click on the link `ImageAPI`. Click on the `GET` options, and then the `TEST` link. You can now test the API Gateway by entering the query string for your photo name you uploaded to the S3 bucket. The action is set to `getLabels`, and the key (in my case) to `IMG_3080.jpeg`:

![Get Labels query](/images/lambda/getLabels_query.png)

When you click on the test link, you should get a successful result like the this:

![Get Labels query](/images/lambda/getLabels_query_result.png)

## Test ServiceFunction deleteImage with API Gateway

Click on the `DELETE` options in the Amazon API Gateway console, and the `TEST` link. 
Fill in the Query Strings field like this (action is `deleteImage` and key is `IMG_3080.jpeg` in my case):

![Get Labels query](/images/lambda/deleteImage_query.png)

The result should be like the following (note the string `deleted bucket object IMG_3080.jpeg`):

![Get Labels query](/images/lambda/deleteImage_query_result.png)

## Conclusion

We have in this blog post introduced Amazon API Gateway, and tested that it works with query parameters to get labels from the DynamoDB database and also delete the image from the API Gateway.

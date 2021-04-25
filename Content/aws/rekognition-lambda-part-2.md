---
date: 2021-04-24 09:34
description: Rekognition Lambda Function with Swift Part 2
tags: lambda, aws, docker, swift
---
###### Published 2021-04-24
# Rekognition Lambda Function with Swift Part 2

In the first [part of](/aws/rekognition-lambda-part-1) this series I showed how to make a simple Lambda function in Swift with the help of the Soto library, which uses the AWS Rekognition machine learning service to find information about photos you upload to your AWS S3 bucket. 

In this blog post I will introduce another Lambda function, the leftmost Lambda function in the image below. The Lambda function will receive an action and a key (AWS S3 key). The key is the name of the photo stored in the S3 bucket, and the action is either `getLabels` which gets the information about a photo you have already uploaded from the DynamoDB database, or `deleteImage` that deletes the photo from the S3 buckets and from the database.
We will make the Lambda function in Swift, and call it `ServiceFunction`.

We will also create a second S3 bucket, to keep a thumbnail of the image we upload. We create the thumbnail with the help of the ImageMagick library. But first I had to make a Swift package of the library, and [this blog post](/aws/use-imagemagick-in-amazon-linux) I made shows how to do this.

Because we have two Swift Lambda functions, both with their own Swift Package Manager and Source folder, we have to make a new `lambda` folder which contains a folder for each of the two Lambda function sources, `rekfunction` and `servicefunction`.

The full code base is available from my [GitHub account](https://github.com/imyrvold/DevhrProjectCICD), and I have a branch for each part of this series. The branch of this part is  `part2`.

![RekFunction](/images/lambda/rekfunction.png)

## Swift Package Manager - rekfunction

Because we are using the ImageMagick library, we have to include it as a dependency from my GitHub repository. For more information about the library, check out my [blog post](/aws/use-imagemagick-in-amazon-linux) about it. Add it to `lambda/rekfunction/Package.swift`.

```
// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "RecognitionFunction",
    dependencies: [
        .package(url: "https://github.com/swift-server/swift-aws-lambda-runtime.git", .upToNextMajor(from: "0.3.0")),
        .package(url: "https://github.com/soto-project/soto.git", from: "5.0.0"),
        .package(url: "https://github.com/imyrvold/CImageMagick.git", from: "1.0.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "RecognitionFunction",
            dependencies: [
                .product(name: "AWSLambdaRuntime", package: "swift-aws-lambda-runtime"),
                .product(name: "AWSLambdaEvents", package: "swift-aws-lambda-runtime"),
                .product(name: "SotoS3", package: "soto"),
                .product(name: "SotoRekognition", package: "soto"),
                .product(name: "SotoDynamoDB", package: "soto")
            ]),
        .testTarget(
            name: "RecognitionFunctionTests",
            dependencies: ["RecognitionFunction"]),
    ]
)
```

## RecognitionFunction

This is the Lambda function we created in [part 1](/aws/rekognition-lambda-part-1), but we need to add the `createThumbnail` and `saveThumbnail` functions to the Lambda Swift function. We add an import statement to import the library. I couldn't get the import of the `CImageMagickMac` to work when compiling for the Macos, but fortunately it works for Linux, and that is important because the Lambda function is going to run in an AmazonLinux2 environment:

```
import AWSLambdaRuntime
import AWSLambdaEvents
import SotoRekognition
import SotoDynamoDB
import SotoS3
import Foundation
#if os(macOS)
import CImageMagickMac
#else
import CImageMagick
#endif
```

The `handle(context:event:)` function first gets the name of the `thumbBucket` S3 bucket by use of the environment variable that is set by the CDK infrastructure code when the bucket is created:

```
func handle(context: Lambda.Context, event: In) -> EventLoopFuture<Out> {
    let db = DynamoDB(client: awsClient, region: .euwest1)
    let rekognitionClient = Rekognition(client: awsClient)
    guard let thumbBucket = Lambda.env("THUMBBUCKET") else { return context.eventLoop.makeSucceededVoidFuture() }
```

We proceed with making the `detectLabelsRequest` object like we did in [part 1](/aws/rekognition-lambda-part-1), by mapping the records of the S3 input event:

```
let futureRecords: [AWSLambdaEvents.S3.Event.Record] = event.records

let futureRecordsResult = futureRecords.map { record -> EventLoopFuture<Out> in
    let safeKey = record.s3.object.key.replacingOccurrences(of: "%3A", with: ":")
    let s3Object = Rekognition.S3Object(bucket: record.s3.bucket.name, name: safeKey)
    let image = Rekognition.Image(s3Object: s3Object)
    let detectLabelsRequest = Rekognition.DetectLabelsRequest(image: image, maxLabels: 10, minConfidence: minConfidence)
```

Because we this time will have to make a thumbnail of the image, we have to get the image from the S3 bucket, and call the `createThumbnail` function to create the thumbnail itself:

```
return getImage(of: record.s3.bucket.name, with: safeKey, context: context)
    .flatMap { output in
        let body = output.body
        guard let data = body?.asData() else { return context.eventLoop.makeSucceededVoidFuture() }
        guard let thumbnail = createThumbnail(for: data, context: context) else { return context.eventLoop.makeSucceededVoidFuture() }
```

Having successfully created the thumbnail, we can now proceed with detecting the labels in the image with the AWS Rekognition machine learning service, saving the labels in the DynamoDB database, and saving the thumbnail to the thumbnail S3 bucket:

```
return rekognitionClient.detectLabels(detectLabelsRequest)
    .flatMap { detectLabelsResponse -> EventLoopFuture<Void> in
        guard let rekLabels = detectLabelsResponse.labels,
              let imageLabelsTable = Lambda.env("TABLE") else {
            return context.eventLoop.makeSucceededFuture(())
        }

        // Instantiate a table resource object of our environment variable
        let labels = rekLabels.compactMap { $0.name }
        let rekEntry = RekEntry(image: safeKey, labels: labels)
        let putRequest = DynamoDB.PutItemCodableInput(item: rekEntry, tableName: imageLabelsTable)

        // Put item into table
        return db.putItem(putRequest)
            .flatMap { result in
                return saveThumbnail(in: thumbBucket, with: safeKey, for: thumbnail).map { _ in }
            }
    }
}
}
```

The complete handle function:

```
func handle(context: Lambda.Context, event: In) -> EventLoopFuture<Out> {
    let db = DynamoDB(client: awsClient, region: .euwest1)
    let rekognitionClient = Rekognition(client: awsClient)
    guard let thumbBucket = Lambda.env("THUMBBUCKET") else { return context.eventLoop.makeSucceededVoidFuture() }

    let futureRecords: [AWSLambdaEvents.S3.Event.Record] = event.records

    let futureRecordsResult = futureRecords.map { record -> EventLoopFuture<Out> in
        let safeKey = record.s3.object.key.replacingOccurrences(of: "%3A", with: ":")
        let s3Object = Rekognition.S3Object(bucket: record.s3.bucket.name, name: safeKey)
        let image = Rekognition.Image(s3Object: s3Object)
        let detectLabelsRequest = Rekognition.DetectLabelsRequest(image: image, maxLabels: 10, minConfidence: minConfidence)

        return getImage(of: record.s3.bucket.name, with: safeKey, context: context)
            .flatMap { output in
                let body = output.body
                guard let data = body?.asData() else { return context.eventLoop.makeSucceededVoidFuture() }
                guard let thumbnail = createThumbnail(for: data, context: context) else { return context.eventLoop.makeSucceededVoidFuture() }

                return rekognitionClient.detectLabels(detectLabelsRequest)
                    .flatMap { detectLabelsResponse -> EventLoopFuture<Void> in
                        guard let rekLabels = detectLabelsResponse.labels,
                              let imageLabelsTable = Lambda.env("TABLE") else {
                            return context.eventLoop.makeSucceededFuture(())
                        }

                        // Instantiate a table resource object of our environment variable
                        let labels = rekLabels.compactMap { $0.name }
                        let rekEntry = RekEntry(image: safeKey, labels: labels)
                        let putRequest = DynamoDB.PutItemCodableInput(item: rekEntry, tableName: imageLabelsTable)

                        // Put item into table
                        return db.putItem(putRequest)
                            .flatMap { result in
                                return saveThumbnail(in: thumbBucket, with: safeKey, for: thumbnail).map { _ in }
                            }
                    }
            }
    }
    
    return EventLoopFuture<Out>.andAllSucceed(futureRecordsResult, on: context.eventLoop)
}
```

This is the `createThumbnail` function that uses the ImageMagick library to create the thumbnail image. The created thumbnail has the height of 100 pixels, and the width is calculated to keep the aspect ratio of the original image:
```
func createThumbnail(for data: Data, context: Lambda.Context) -> Data? {
    let fileManager = FileManager.default
    let path = "/tmp/image.jpeg"
    let thumbnailpath = "/tmp/thumbnail.jpeg"
    let bool = fileManager.createFile(atPath: path, contents: data, attributes: nil)

    MagickWandGenesis()
    let wand = NewMagickWand()

    let status: MagickBooleanType = MagickReadImage(wand, path)
    if status == MagickFalse {
        context.logger.info("Error reading the image")
    } else {
        let width = MagickGetImageWidth(wand)
        let height = MagickGetImageHeight(wand)
        let newHeight = 100
        let newWidth = 100 * width / height
        MagickResizeImage(wand, newWidth, newHeight, LanczosFilter,1.0)
        MagickWriteImage(wand, thumbnailpath)
    }
    DestroyMagickWand(wand)
    MagickWandTerminus()
    
    return fileManager.contents(atPath: thumbnailpath)
}
```

The `getImage` function that grabs the image from the S3 bucket:

```
func getImage( of bucket: String, with thekey: String, context: Lambda.Context) -> EventLoopFuture<SotoS3.S3.GetObjectOutput> {
    let s3 = S3(client: awsClient)
    let safeKey = thekey.replacingOccurrences(of: "%3A", with: ":")
    guard let key = safeKey.removingPercentEncoding else { return context.eventLoop.makeSucceededFuture(S3.GetObjectOutput()) }
    let getObjectRequest = S3.GetObjectRequest(bucket: bucket, key: key)

    return s3.getObject(getObjectRequest)
}
```

The `saveThumbnail` function that saves the thumbnail to the thumbnail S3 bucket:

```
func saveThumbnail(in bucket: String, with thekey: String, for data: Data) -> EventLoopFuture<SotoS3.S3.PutObjectOutput> {
    let s3 = S3(client: awsClient)
    let bodyData = AWSPayload.data(data)
    
    let putRequest = SotoS3.S3.PutObjectRequest(
        acl: S3.ObjectCannedACL.publicRead,
        body: bodyData,
        bucket: bucket,
        key: thekey
    )
    
    return s3.putObject(putRequest)
}
```

## ServiceFunction

The `Package.swift` only needs the `SotoS3` and `SotoDynamoDB` dependencies:

```
// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "servicefunction",
    dependencies: [
        .package(url: "https://github.com/swift-server/swift-aws-lambda-runtime.git", .upToNextMajor(from: "0.3.0")),
        .package(url: "https://github.com/soto-project/soto.git", from: "5.0.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "servicefunction",
            dependencies: [
                .product(name: "AWSLambdaRuntime", package: "swift-aws-lambda-runtime"),
                .product(name: "AWSLambdaEvents", package: "swift-aws-lambda-runtime"),
                .product(name: "SotoS3", package: "soto"),
                .product(name: "SotoDynamoDB", package: "soto")
            ]),
        .testTarget(
            name: "servicefunctionTests",
            dependencies: ["servicefunction"]),
    ]
)
```

These are the model structs in the models folder. The input to the Lambda function is an action and a key. The key is the name of the photo stored in the S3 bucket, as well as the name of the thumbnail stored in the thumbnail S3 bucket. The action for the Lambda function is either `getLabels` to get the labels stored in the DynamoDB database for the photo, or `deleteImage` to delete the photo from the image bucket and thumbnail bucket, and delete the entry in the DynamoDB database.

The `LabelsOutput` is the output from the Lambda function when we use the `getLabels` action, and the `DeleteOutput` is the output when we use the `deleteImage` action.

```
struct Input: Codable {
    enum Action: String, Codable {
        case getLabels, deleteImage
    }

    let action: Action
    let key: String
}

struct LabelsOutput: Codable {
    let labels: [String]
}

struct RekEntry: Codable {
    let image: String
    let labels: [String]
}

struct DeleteOutput: Codable {
    let result: String
}
```

The `ServiceHandler` then sets the input and output in this way:

```
struct ServiceHandler: EventLoopLambdaHandler {
    typealias In = Input
    typealias Out = APIGateway.Response
    
    let awsClient: AWSClient
```

And the `handle` function in the `ServiceHandler`. We use a switch statement to determine the action to use in the handler, and calls `getLabels` or `deleteImage` function:

```
func handle(context: Lambda.Context, event: In) -> EventLoopFuture<Out> {
    let input = event

    switch input.action {
    case .getLabels:
        return getLabels(with: input.key, context: context)
            .flatMap { result in
                switch result {
                case .success(let imageLabel):
                    let labels = imageLabel.labels

                    let output = LabelsOutput(labels: labels)
                    let apigatewayOutput = APIGateway.Response(with: output, statusCode: .ok)
                    
                    return context.eventLoop.makeSucceededFuture(apigatewayOutput)
                case .failure(let error):
                    let apigatewayOutput = APIGateway.Response(with: error, statusCode: .notFound)
                    
                    return context.eventLoop.makeSucceededFuture(apigatewayOutput)
                }
            }
    case .deleteImage:
        return deleteImage(with: input.key, context: context)
            .flatMap { result in
                switch result {
                case .success(let text):
                    let apigatewayOutput = APIGateway.Response(with: text, statusCode: .ok)
                    
                    return context.eventLoop.makeSucceededFuture(apigatewayOutput)
                case .failure(let error):
                    let apigatewayOutput = APIGateway.Response(with: error, statusCode: .internalServerError)

                    return context.eventLoop.makeSucceededFuture(apigatewayOutput)
                }
            }
    }

}
```

The `getLabels` function:

```
func getLabels(with key: String, context: Lambda.Context) -> EventLoopFuture<Result<RekEntry, APIError>> {
    guard let imageLabelsTable = Lambda.env("TABLE") else {
        return context.eventLoop.makeSucceededFuture(Result.failure(APIError.getLabelsError))
    }
    let db = DynamoDB(client: awsClient, region: .euwest1)
    let input = DynamoDB.GetItemInput(key: ["image": .s(key)], tableName: imageLabelsTable)
    
    return db.getItem(input, type: RekEntry.self)
        .flatMap { output in
            guard let rekEntry = output.item else {
                return context.eventLoop.makeSucceededFuture(Result.failure(APIError.getLabelsError))
            }
            return context.eventLoop.makeSucceededFuture(Result.success(rekEntry))
        }
}
```

The `deleteImage` function:

```
func deleteImage(with key: String, context: Lambda.Context) -> EventLoopFuture<Result<String, APIError>> {
    guard let imageLabelsTable = Lambda.env("TABLE"), let bucketName = Lambda.env("BUCKET"), let thumbBucketName = Lambda.env("THUMBBUCKET") else {
        return context.eventLoop.makeSucceededFuture(Result.failure(APIError.deleteError))
    }
    
    let s3 = S3(client: awsClient)
    let db = DynamoDB(client: awsClient, region: .euwest1)
    let input = DynamoDB.DeleteItemInput(key: ["image": .s(key)], tableName: imageLabelsTable)
    
    let deleteObjectRequest = S3.DeleteObjectRequest(bucket: bucketName, key: key)
    let deleteThumbRequest = S3.DeleteObjectRequest(bucket: thumbBucketName, key: key)

    return db.deleteItem(input)
        .flatMap { _  -> EventLoopFuture<Result<String, APIError>> in
            return s3.deleteObject(deleteObjectRequest)
                .flatMap { _ in
                    return context.eventLoop.makeSucceededFuture(Result<String, APIError>.success("deleted bucket object \(key)"))
                }
        }
        .flatMap { _ -> EventLoopFuture<Result<String, APIError>> in
            return s3.deleteObject(deleteThumbRequest)
                .flatMap { _ in
                    return context.eventLoop.makeSucceededFuture(Result<String, APIError>.success("deleted bucket object \(key)"))
                }
        }
}
```

## CDK Infrastructure Code

We are in a new branch `part2`, so we need to make sure that the CI/CD infrastructure code in CDK checks out the correct branch. This is in the `cdk/lib/devhr-project-cicd-infra.ts` file. This is the only change we have in this file. Replace `main` with `part2`:

```
import * as cdk from '@aws-cdk/core';
import * as codepipeline from '@aws-cdk/aws-codepipeline';
import * as codepipeline_actions from '@aws-cdk/aws-codepipeline-actions';
import * as ecr from '@aws-cdk/aws-ecr';
import * as iam from '@aws-cdk/aws-iam';
import * as pipelines from '@aws-cdk/pipelines';
import { LambdaDeploymentStage } from './lambda-deployment';

export class DevhrProjectCicdInfraStack extends cdk.Stack {
    constructor(scope: cdk.Construct, id: string, props?: cdk.StackProps) {
        super(scope, id, props)

        const sourceArtifact = new codepipeline.Artifact();
        const cdkOutputArtifact = new codepipeline.Artifact();
        
        const pipeline = new pipelines.CdkPipeline(this, 'CdkPipeline', {
            crossAccountKeys: false,
            pipelineName: 'devhr-project-pipeline',
            cloudAssemblyArtifact: cdkOutputArtifact,

            sourceAction: new codepipeline_actions.GitHubSourceAction({
                actionName: 'DownloadSources',
                owner: 'imyrvold',
                repo: 'DevhrProjectCICD',
                branch: 'part2',
```

We have a new S3 bucket for the resized image, and a new Lambda function, so we have to add these to the `cdk/lib/devhr-project-stack.ts`. First, add the name of the new resized bucket:

```
import * as cdk from '@aws-cdk/core'
import * as s3 from '@aws-cdk/aws-s3'
import * as lambda from '@aws-cdk/aws-lambda'
import * as dynamodb from '@aws-cdk/aws-dynamodb'
import { Duration } from '@aws-cdk/core'
import * as iam from '@aws-cdk/aws-iam'
import * as event_sources from '@aws-cdk/aws-lambda-event-sources'

const imageBucketName = 'cdk-rekn-imagebucket'
const resizedBucketName = imageBucketName + "-resized"
```
Then, add the path to the dockerfile for the `rekfunction` and the `servicefunction`:

```
export class DevhrProjectStack extends cdk.Stack {
  constructor(scope: cdk.Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props)

    const dockerfile = '../lambda/rekfunction/';
    const serviceDockerfile = '../lambda/servicefunction/';
```

After the code that defines the Image Bucket, add the Thumbnail Bucket:

```
// =================================================================================
// Image Bucket
// =================================================================================
const imageBucket = new s3.Bucket(this, imageBucketName, {
  removalPolicy: cdk.RemovalPolicy.DESTROY
})
new cdk.CfnOutput(this, 'imageBucket', { value: imageBucket.bucketName })

// =================================================================================
// Thumbnail Bucket
// =================================================================================
const resizedBucket = new s3.Bucket(this, resizedBucketName, {
  removalPolicy: cdk.RemovalPolicy.DESTROY
})
new cdk.CfnOutput(this, 'resizedBucket', { value: resizedBucket.bucketName })
```

After the Amazon DynamoDB code, which is unchanged, we add the environment variable for the thumbbucket. We also increase the timeout to 30 seconds. The Lambda function needs more time to create the thumbnail:

```
// =================================================================================
// Amazon DynamoDB table for storing image labels
// =================================================================================
const table = new dynamodb.Table(this, 'ImageLabels', {
  tableName: 'ImageLabels',
  partitionKey: { name: 'image', type: dynamodb.AttributeType.STRING },
  removalPolicy: cdk.RemovalPolicy.DESTROY
})
new cdk.CfnOutput(this, 'ddbTable', { value: table.tableName })

// =================================================================================
// Building our AWS Lambda Function; compute for our serverless microservice
// =================================================================================
const rekFn = new lambda.DockerImageFunction(this, 'recognitionFunction', {
  functionName: 'recognitionFunction',
  code: lambda.DockerImageCode.fromImageAsset(dockerfile),
  environment: {
    'TABLE': table.tableName,
    'BUCKET': imageBucket.bucketName,
    'THUMBBUCKET': resizedBucket.bucketName
  },
  timeout: Duration.seconds(30)
});
```

We also need to grant the permission to put the image to the thumbnail bucket for the Lambda function:

```
rekFn.addEventSource(new event_sources.S3EventSource(imageBucket, { events: [s3.EventType.OBJECT_CREATED] }))
imageBucket.grantRead(rekFn)
resizedBucket.grantPut(rekFn)
resizedBucket.grantPutAcl(rekFn)
table.grantWriteData(rekFn)

rekFn.addToRolePolicy(new iam.PolicyStatement({
  effect: iam.Effect.ALLOW,
  actions: ['rekognition:DetectLabels'],
  resources: ['*']
}))
```

At last, we add the new Lambda function for the `serviceFunction`:

```
// =====================================================================================
// Lambda for Synchronous Front End
// =====================================================================================
​  const serviceFn = new lambda.DockerImageFunction(this, 'serviceFunction', {
  functionName: 'serviceFunction',
  code: lambda.DockerImageCode.fromImageAsset(serviceDockerfile),
  environment: {
    'TABLE': table.tableName,
    'BUCKET': imageBucket.bucketName,
    'THUMBBUCKET': resizedBucket.bucketName
  },
  timeout: Duration.seconds(30)
});

imageBucket.grantWrite(serviceFn);
resizedBucket.grantWrite(serviceFn);
table.grantReadWriteData(serviceFn);
}
}
```

## Test Rekognition with Lambda

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

Check that the image has been uploaded with:

`aws s3 ls s3://lambdadeploymentstage-de-cdkreknimagebucketa588dc-1123ayav2rc42` 

and check that the thumbnail has been created in the other S3 bucket:

`aws s3 ls s3://lambdadeploymentstage-de-cdkreknimagebucketresize-12azqz1h8qxs5`.

If you want, you could now copy the resized photo back to your disk, and open it in Preview to see that it is in fact resized:

`aws s3 cp s3://lambdadeploymentstage-de-cdkreknimagebucketresize-12azqz1h8qxs5/IMG_3080.jpeg ~/Desktop/`

`open -a Preview ~/Desktop/IMG_3080.jpeg`

Also check that DynamoDB has got the labels for the photo:

`aws dynamodb scan --table-name ImageLabels`

## Test ServiceFunction Lambda

To test the serviceFunction, open up the Lambda Function console with your browser, and select the `serviceFunction` link.
Select the Test tab, and adjust the json to something like this. Use your own key for the photo name:

![Test getLabels](/images/lambda/getLabels.png)

The result should be something like this:

![Test getLabels](/images/lambda/getLabelsResult.png)

Now, set the action to `deleteImage`, and click the Test button again.
You should again get a successful result, and to see that the images are really deleted from the S3 buckets, run the aws commands again:

`aws s3 ls s3://lambdadeploymentstage-de-cdkreknimagebucketa588dc-1123ayav2rc42`
`aws s3 ls s3://lambdadeploymentstage-de-cdkreknimagebucketresize-12azqz1h8qxs5`

You should get empty result now. And do the same with the database:

`aws dynamodb scan --table-name ImageLabels`

This should also return empty.

## Conclusion

We have in this part introduced a new resized bucket and a new Lambda function, and tested that we can in fact resize an image that we have stored in an S3 bucket, and we can use the new Lambda function to get information about the stored photo, and also delete the image.

In my [next blog post](/aws/rekognition-lambda-part-3) in this serial, I will show how to connect the AWS API Gateway (Rest API) to the Lambda serviceFunction.

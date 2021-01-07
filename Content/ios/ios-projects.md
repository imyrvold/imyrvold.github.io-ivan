---
date: 2021-01-07 10:00
description: iOS projects I have worked on
tags: ios, swift
---
###### Published 2021-01-07
# iOS projects I have worked on

I have been involved in several iOS projects, some I have developed from scratch in Swift, like [RegIT](https://regit-app.no).

[Sporty app](https://www.sportyapp.com/nb#index) is an app that I converted from Objective-C to the more modern language Swift.

[Abax Triplog](https://apps.apple.com/no/app/abax-triplog/id459415370?l=nb) is also an app I converted from Objective-C to Swift.

Dune is a private project that I have been working on for about a year. The frontend for this project is a SwiftUI app that runs on iPhone/iPad and macos.
The backend is a server-side Swift backend server, using the [Vapor framework](https://vapor.codes), which is a non-blocking, event-driven architecture built on top of [SwiftNIO](https://github.com/apple/swift-nio). The backend runs on AWS ECS Fargate, and the infrastructure on AWS is developed with [AWS Cloud Development Kit](https://aws.amazon.com/cdk/) as a Continuous Integration and Delivery (CI/CD) pipeline.

## RegIT App

![RegIT Din private journal](/images/iOS/regit-din-private-journal.png)

RegIT app is an app you can use to map allergens and other food intake sicknesses. You can make a PDF at the end of a month which you can send to the doctor, that contains a table with all recorded symptoms during the month. That is a great help for parents handling children with these sicknesses and allergens.
The app is translated to Sami, so that a Sami user will have everything in the app shown in Sami.

When I joined the RegIT project, there was already an iOS and Android app developed, and on the AppStore. The iOS app was a hybrid app, developed with web technology. The RegIT team was not satisfied with the solution, and wanted a native iOS app. I programmed the app from scratch in Swift, and did not use anything from the old hybrid app. The app connected to a Firebase backend to persist data, and this also made it possible to use Android and web to login and be presented the same recorded data.

The app is also running natively on iPad.
RegIT app I am continuously maintaining in my free time.

The app is GDPR compliant, and the user must approve GDPR when a new user is registered:
![RegIT register](/images/iOS/regit-create-user.png)

## Abax Triplog

When I joined ABAX in Larvik, the Triplog app had already been in the market for a few years. It was programmed in Objective-C, and I immediately started converting it to Swift. As the Triplog app is a complicated and large app, this was a big project. The app connected to backend servers that was developed internally at ABAX. I was working together with the Android developer, so that the apps would have the same graphical user interface on both platforms.

![ABAX Triplog](/images/iOS/abax-triplog.png)

## Sporty App

Sporty AS is a Norwegian startup company based in Oslo which was started by Christian Ringnes Jr. and his gründer comrades Mathias Mikkelsen and Christopher Onsrud after a trip to California to kick-start the app. The app was meant to be a social app for people who wanted to participate in different sport activities by inviting friends through the app.

![Activities with People Nearby](/images/iOS/sporty-activities-nearby.png)


In 2015 it was decided to rewrite the app to make it possible to book tennis courts and other activities, and pay the bookings through the app.
I joined the company in early 2016 to make this possible. The backend for the app was **Parse**, and just before I joined the company, Facebook decided to shut down the service. This made it urgent to find a new backend solution, and we decided to use Google's **Firebase**.

I converted the app to Swift and to use the new Firebase backend. I also implemented a payment system in the app using **Stripe**.

![Sporty App](/images/iOS/sporty-app.jpeg) ![Sporty Booking](/images/iOS/sporty-booking.jpeg)

## Dune project

This is a project I have been working on when I had time, mostly during weekends. It isn't yet on the Appstore, and I am unsure if I will ever publish it there. I am using this project to explore the newest technologies in frontend, backend and AWS.
The Dune iPhone/iPad MacOS app uses [SwiftUI](https://developer.apple.com/documentation/swiftui/), the new declarative framework Apple introduced during WWDC 2019.
The backend is programmed with [Vapor framework](https://vapor.codes), and I have developed a CI/CD pipeline with [AWS Cloud Development Kit](https://aws.amazon.com/cdk/), containerized the app and running together with MongoDB on AWS ECS Fargate.
I have made a [tutorial how to use CDK to make a CI/CD pipeline](/vapor/cdk-pipeline-part-1) and have deployed the Dune backend the same way in AWS.
Whenever I push changes to the GitHub repository of the backend, the pipeline builds a new Docker container and deploys this automatically together with a MongoDB container to AWS ECS Fargate.

The Dune iOS app will eventually make it possible to connect and manage IoT devices, but at the moment I am building the infrastructure to make this possible.

![Dune appearance](/images/iOS/dune-appearance.png)


---
date: 2023-05-28 14:09
description: Deploy Vapor app on Kubernetes
tags: vapor, kubernetes, mongodb
---
###### Published 2023-05-28
# Deploy Vapor app on Kubernetes

## The project

I have on previous blog posts described how to deploy Vapor microservices on AWS. In this blog post, I will show how to do the same on Kubernetes. I will not go into details on the Vapor project itself, as you can see in my previous blog post how to deal with Vapor, but concentrate on how to handle the Kubernetes side to spin up the pods for the UsersService.

I have the finished Vapor project in a private repository at https://github.com/shortcut/UserModelsPackage.git , so for those that have access to that repository can clone it directly.

I have also a SwiftUI project Vorian that will use the Vapor backend to register and login to. UsersService is just one of the microservices that I intend to use as a backend to Vorian, I will later on also add another microservice as another Kubernetes service.

## Kubernetes

In the Kubernetes group in the project, I have prepared the `Deployment` yaml file that will spin up the Kubernetes service on your Mac or on a public cloud service like Google Cloud.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: users-service
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      bb: users
  template:
    metadata:
      labels:
        bb: users
    spec:
      containers:
      - name: users-service
        image: imyrvold/users-service:latest
        imagePullPolicy: Never
---
apiVersion: v1
kind: Service
metadata:
  name: users-entrypoint
  namespace: default
spec:
  type: NodePort
  selector:
    bb: users
  ports:
  - port: 8080
    targetPort: 8080
    nodePort: 30002
```

The container image used is an image that I have prepared, and it will be pulled from my public Docker Hub repository.

To make a container image, you have to navigate to the root of the project with your favorite terminal app, where the `Dockerfile` and the `docker-compose.yaml` files are, and execute the command

`docker compose build`

This will start building the docker image, and result in a docker image `users-service`. You can list out the images you have with the `docker images` command on your terminal.

Tag the image with your name, I do it with the command

`docker tag users-service` imyrvold/users-service:latest`

and then push it to the public Docker hub repository with 

`docker push imyrvold/users-service:latest`

When that is done, start up the Kubernetes service from the Kubernetes folder with

`kubectl apply -f bb.yaml`

(You must have kubectl installed for this, get it with `brew install kubectl`).

The name of the file can be anything, I just named it `bb.yaml` for lack of a better name.

The service should now be visible from your Docker Desktop.

We can use curl to see if the service runs normally, because it has a public health endpoint we can test. I use the fantastic Warp terminal on my Mac, and have prepared Warp workflows for all the curl commands we can use. Those are in the hidden folder `.warp` in the project root. So if you are using Warp, you can just press `control shift R` in the Warp terminal, find the `/health` endpoint and replace port 8080 with the nodePort we have in the `bb.yaml` file. 

```
curl -i --request GET \
 http://localhost:30002/api/users/health
```

If you want to test registering yourself, you can use the endpoint `/users/register` to POST your credentials. This endpoint is also in the Warp workflows:

```
curl -i --request POST \
--header "Content-Type: application/json" \
--data '{ "firstName": "Ivan", "lastName": "Myrvold", "email": "ivan+blabla@myrvold.org", "password": "••••••••••" }' \
http://localhost:30002/api/users/register
```

Use your email and if you are testing this repeatedly, it is handy to use the Google alias if the email is a Google account (write +whatever before the @ character).

Having done that, we can login to obtain a jwt access and refresh token, to be able to use the REST API's' that are secured with JWT authentication. 

```
curl -i --request POST \
--header "Content-Type: application/json" \
--data '{ "email": "ivan@myrvold.org", "password": "••••••••••" }' \
http://localhost:30002/api/users/login
```

## Shared Swift Packages

I have prepared a Swift package, that contains the models used in the Vapor project and also in the Vorian SwiftUI project I will showcase using the UsersService to register and login to. To be able to have a shared model package between backend and frontend makes it very easy to keep the models for frontend and backend in sync. The package can be accessed with the URL `https://github.com/shortcut/UserModelsPackage.git` and is a public repository.


## Vorian SwiftUI app

The Vorian app is a SwiftUI app that will show electricity prices, using public REST API's. If you register and login using the Vapor UsersService running in Kubernetes on your computer or on a public cloud service, you can use secure REST API to get more value out of the app. The app is only meant to be used as a demonstration app.

More to follow...

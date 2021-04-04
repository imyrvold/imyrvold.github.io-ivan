---
date: 2021-04-03 18:40
description: Use ImageMagick in Amazon Linux 2
tags: aws, docker, swift
---
###### Published 2021-04-03
# Use ImageMagick in Amazon Linux 2

For a AWS Lambda function I am planning to develop, I needed some way to manipulate images. Because I am using Swift for the Lambda function, it needs to work in Swift on Amazon Linux 2.

I found a [blog post](https://mikemikina.com/blog/watermarking-photos-with-imagemagick-vapor-3-and-swift-on-macos-and-linux/) where the author used [ImageMagick](https://imagemagick.org/index.php) wrapping ImageMagick into a Swift package. That sounded perfect for me.  I tried installing ImageMagick on Amazon Linux 2, and that installed the library without a problem. But making a Swift Package was more difficult than I first thought, mainly because the examples of how to do it that I found googling the Internet was for the most part outdated or didn't work that well with Amazon Linux. One good source I found was in [How to wrap a C library in Swift](https://www.hackingwithswift.com/articles/87/how-to-wrap-a-c-library-in-swift) and [Apple's Swift Package Manager GitHub repository](https://github.com/apple/swift-package-manager/blob/main/Documentation/Usage.md#c-language-targets).

This blog post shows how to make the Swift package for ImageMagick using the above mentioned resources. If you want to follow, make sure you have docker installed on your Mac (or Windows).

## Make a Dockerfile for Amazon Linux 2

There is an official docker image for Swift on Amazon Linux 2, that I am using. First, make a new folder where you make a new docker file. Call the folder what you want, I called mine `sim`:

`mkdir sim && cd sim`

In the folder, make a new file with name `Dockerfile` with the content:

```
FROM swift:5.3.2-amazonlinux2
RUN yum makecache fast
RUN yum -y install ImageMagick ImageMagick-devel

COPY . .

WORKDIR /ImageMagickTest
```

## Make ImageMagick wrapper

In Apple's Swift Package Manager repository, they write this:

> The convention we hope the community will adopt is to prefix such modules with C and to camelcase the modules as per Swift module name conventions. Then the community is free to name another module simply libgit which contains more “Swifty” function wrappers around the raw C interface.

I decided to prefix ImageMagick as adviced above, making the wrapper. Make a new folder:

`mkdir CImageMagick && cd CImageMagick`

Now we can use Swift Package Manager to make an empty package, with a type of system module:

`swift package init --type system-module`

Modify the Package.swift to look like this:

```
// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(name: "CImageMagick", pkgConfig: "ImageMagick")
```

By including the `pkgConfig` parameter in the package, Swift Package Manager will be able to figure out all the include and library search paths. I didn't know this when I first tried to use the package in a small test app, and I always got compile errors until I included the parameter. Then it suddenly worked.

In `module.modulemap` modify the content to this:

```
module CImageMagick [system] {
  header "/usr/include/ImageMagick-6/magick/ImageMagick.h"
  header "/usr/include/ImageMagick-6/magick/MagickCore.h"
  header "/usr/include/ImageMagick-6/wand/MagickWand.h"
  link "MagickWand-6.Q16"
  link "MagickCore-6.Q16"
  export *
}
```

This is how we show Swift Package Manager where all the header files are installed on the machine we use.
To be able to use this module in a test app, we need to make a git repository for it locally:

`git init`
`git add .`
`git commit -m "Initial commit"`
`git tag 1.0.0`

Now the Swift module is ready for the test app

## Test the Swift module on Amazon Linux 2

Make a new directory directly under `sim`, naming it e.g. `ImageMagickTest`. In the new folder, use Swift Package Manager to make a new executable app:

`swift package init --type executable`

Modify `Package.swift` to the following:

```
// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ImageMagickTest",
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        .package(url: "../CImageMagick", from: "1.0.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "ImageMagickTest",
            dependencies: []),
        .testTarget(
            name: "ImageMagickTestTests",
            dependencies: ["ImageMagickTest"]),
    ]
)
```

And modify the `main.swift` file to this:

```
import CImageMagick

print("Hello, world!")

MagickWandGenesis()
let wand = NewMagickWand()
let pixel = NewPixelWand()

PixelSetColor(pixel, "red")
MagickSetBackgroundColor(wand, pixel)

MagickNewImage(wand, 100, 100, pixel)
MagickWriteImage(wand, "redsquare.jpg")

DestroyMagickWand(wand)
DestroyPixelWand(pixel)
MagickWandTerminus()
```

To be able to use the Swift module in a Amazon Linux application, we need to either publish the `CImageMagick` module to a public git repository, or make the git repository using the docker file. I have already published the module on [my public repository](https://github.com/imyrvold/CImageMagick.git), feel free to use it if you want.


With Terminal.app, change directory to `sim`, where the `Dockerfile` is, and build the new image. Call the image whatever you want:

`docker build -t sim:latest .`

If you run the docker container from the image interactively, with parameter --volume "$(pwd)/:/src", then you can edit the source in main.swift with Xcode, but compile it in the container itself:

`docker run --rm \`
`--volume "$(pwd)/:/src" \`
`--workdir "/src/" \`
`-it sim bash`

You can now build the `ImageMagickTest` using Swift from the docker container:

`swift build`

You should now have a `build` folder, and can run the application from there:

`.build/debug/ImageMagickTest`

This should print out a `Hello, world!` in terminal, and you should also find a new file called `redsquare.jpg` in Finder in the folder `ImageMagickTest`

If you place a photo in the `ImageMagickTest` folder, and modify `main.swift` to the following code, you will be able to resize the photo. Just replace the `<photo file name>` with the name of your photo:

```
import CImageMagick

MagickWandGenesis()
let wand = NewMagickWand()

let status: MagickBooleanType = MagickReadImage(wand, "<photo file name>")
if status == MagickFalse {
    print("Error reading the image")
} else {
    let width = MagickGetImageWidth(wand)
    let height = MagickGetImageHeight(wand)
    let newHeight = 100
    let newWidth = 100 * width / height
    MagickResizeImage(wand, newWidth, newHeight, LanczosFilter,1.0)
}
MagickWriteImage(wand, "thumbnail.jpg")

DestroyMagickWand(wand)
MagickWandTerminus()
```

After a `swift build` and running the code with `.build/debug/ImageMagickTest`, you should find a thumbnail of your photo with name `thumbnail.jpg` in Finder folder `ImageMagickTest`.

## Conclusion

We have successfully made a new Swift module called `CImageMagick` using the naming convention wants us to adopt. We have imported `CImageMagick` into a Swift test application running on Amazon Linux 2 in a docker container, and found that it works fine there.

If you want to use my Swift repository, use the `Dockerfile` as we originally created it, and replace the `.package(url: "../CImageMagick", from: "1.0.0")` in your Swift Package Manager app (`Package.swift`) with:
`.package(url: "https://github.com/imyrvold/CImageMagick.git", from: "1.0.0")`



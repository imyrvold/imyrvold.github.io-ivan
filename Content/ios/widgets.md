---
date: 2022-12-31 13:14
description: Make widgets with SwiftUI
tags: ios, swift, charts, widgets
---
###### Published 2022-12-31
# Make widgets with SwiftUI

## Why widgets? ##

With iOS 14 in 2020 Apple introduced the WidgetKit that makes it possible to make small SwiftUI views that can be shown in the home screen. Widgets support multiple sizes, and the user can easily search for and add widgets to the home screen.

Last summer, at WWDC in June 2022, Apple came up with Swift Charts, which enables a SwiftUI developer to add powerful charts in his app. I was wondering if it was possible to add SwiftUI charts in a widget, because that would enable me to make a widget that shows the daily electricity price during the day in a small widget. As I am the iOS developer of the iOS app elKompis, which is an app that a user can use to have a good overview of his electricity consumption of his house or apartment, a widget would be a cool addition to the app.

The company, `elKompis`, that I am hired to develop the app for, have encouraged me to look into developing a widget, so I decided to follow through with it during my off time.

## Create the widget ##
A widget is created in Xcode by adding a new `Target` of type Widget Extension. A cool thing about a widget extension is that it have it's own life cycle, and not dependent on the life cycle of the parent app. As such, it can use the latest iOS version, even as the parent app is pinned at a previous iOS version. `elKompis`, the parent app, is set to using iOS 15.4, but for the widget extension we can use 16.1 or later, and therefore enable us to use Swift Charts.

##  How to get the electricity prices ##
For the app `elKompis` we are using an API to our backend server to fetch the electricity prices. I first looked into using the same API from the widget itself, but that proved difficult, because the APIs are protected by JWT authentication, and I found it impossible to obtain a JWT token from the widget extension itself.

But a second option is to use a shared file, so that the parent app `elKompis` can get the prices from the protected API, and write it to a file, and the widget extension can read the file and get the prices that way.

Now, getting the prices would not be a problem, but when should the parent app fetch the prices? When the app is not running, it is not doing any API fetching from the backend server. This would  not be a good thing for the widget, because if the user is not running the app for several days, the widget extension will not have up to date prices to show in the widget view.

I knew I would have to look into background tasks. 

## Background Tasks ##
Apple added the framework `BackgroundTasks` for iOS 13. One of the tasks I can use in the framework is `BGAppRefreshTasks`, which gives the app 30 seconds to do the task it needs to do. That should be enough time for the parent app to fetch the electricity prices and write it to a shared file.

The parent app `elKompis` would need to have the background modes in Xcode `Signing & Capabilities` Background fetch, and Background processing ticked off to make the background tasks work. Luckily, they already were.
Next, I needed to set the `Permitted background task scheduler` in the Info.plist for `BGAppRefreshTaskRequest` for the `elKompis` target.



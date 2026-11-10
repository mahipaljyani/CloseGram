# CloseGram

Instagram for the people you actually know. No Reels, no Explore rabbit hole, no suggested posts, no ads.

CloseGram is a small, open-source iPhone app that opens Instagram's website inside a clean wrapper and strips out the parts built to keep you scrolling. You keep your friends' posts, stories if you want them, and your DMs.

Everything runs on your phone. There is no server, no account, no analytics.

## What it does

Every feature is a switch in Settings (the tab on the right edge of the screen).

**Feed**
- **Following only, newest first.** Opens Instagram's Following view instead of the algorithmic feed.
- **Hide suggested posts and ads.**
- **Hide reels in the feed**, and **block the Reels tab.** A reel a friend sends you still plays, as one video with nothing to swipe to.
- **Hide the Explore grid.** Search still works.
- **Stop the feed** after 10, 20, 30 or 50 posts, or **at posts you've already seen**, with a "you're caught up" message.
- **Hide likes and counts**, and **hide the stories bar.**

**Messages**
- **Messages only.** Hides the feed, Explore and profiles, and opens straight to your inbox.
- **Quiet hours.** Switches to messages only between the times you pick, such as 10 pm to 7 am.

**Opening the app**
- **Pause before opening.** Asks what you're here for, and waits 5 seconds.
- **Daily limit.** After your limit, a "done for today" screen. You can get more time by typing a sentence or waiting a minute.
- **Face ID lock.**
- **Lock the real Instagram app** with Screen Time, so you use CloseGram instead. Unlock it for 15 minutes when you need it, for example to post a reel, and it locks again by itself.

**Look**
- **Grayscale**, to make the feed less pulling.

## How it works

iOS does not let one app change what another app shows, so CloseGram cannot edit the real Instagram app. Instead it loads `instagram.com` in a `WKWebView` and injects a script at page load that hides elements and redirects certain pages. The whole blocker is one file: [`Sources/InjectedScript.swift`](Sources/InjectedScript.swift).

Your login is a normal Instagram web session. Your password goes straight to Instagram, and the session cookie stays in the app's web storage on your phone. Settings, screen time and the list of posts you've seen are stored on the device only.

For it to work, delete the real Instagram app, or turn on "Lock the Instagram app" in Settings.

## Limits

- **No DM push notifications.** The website cannot send them to a web view.
- **Posting is whatever Instagram's website supports.** Photos and carousels work; some story and reel tools do not.
- **Instagram changes its website.** When something stops being hidden, the matching rule in `InjectedScript.swift` needs an update. The rules match on links, labels and text, never on Instagram's generated class names, so they break less often. Some text matches are English only.

## Build and install

You need a Mac with Xcode (a version that supports your iPhone's iOS), [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`), and an Apple ID. A free Apple ID works, but the app expires after 7 days and needs reinstalling; a paid developer account lasts a year.

```sh
git clone https://github.com/mahipaljyani/CloseGram.git
cd CloseGram
cp Config/Local.xcconfig.example Config/Local.xcconfig
# edit Config/Local.xcconfig: set your team ID and a bundle ID of your own
xcodegen generate
open CloseGram.xcodeproj
```

The Instagram app lock uses Apple's Family Controls, which needs a paid developer account. It works in your own development builds; TestFlight and App Store builds need Apple to approve "Family Controls (Distribution)" for the app and its `.lockmonitor` extension.

Then pick your iPhone in Xcode and press Run. Or, with the phone plugged in, unlocked and in Developer Mode, run `./install.sh`.

## Contributing

The most useful contributions are fixes when Instagram changes its website. Please describe what stopped working and on which page.

Debug builds include a small helper for that: JavaScript written to the app's `Documents/eval.js` runs in the page, and the result appears in `Documents/eval.out`. In the simulator, find the folder with `xcrun simctl get_app_container booted <bundle id> data`.

## Disclaimer

CloseGram is an independent project. It is not affiliated with, endorsed by or connected to Instagram or Meta. Instagram is a trademark of Meta Platforms, Inc. CloseGram shows Instagram's own website and does not use any private API. Use it with your own account, at your own risk.

## License

[MIT](LICENSE)

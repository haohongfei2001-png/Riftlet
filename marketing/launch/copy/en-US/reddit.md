# Reddit

## Post title

I made a Mac utility for the step between taking a screenshot and attaching it to ChatGPT

## Short version

Riftlet keeps new screenshots at the edge of your Mac screen so you can choose one by sight and attach it to the ChatGPT draft open in Chrome.

## Post

Say you're comparing two tidal maps. The question is about the same bend in the shoreline on each map. The two screenshot names tell you when you took them. The pictures tell you which is which.

Riftlet is a small Mac app I made for that moment. Take your normal screenshot, bring the ChatGPT draft you're writing in to the front in Google Chrome, and click the crop on the edge of your screen. Only the image you choose goes to ChatGPT. You can keep editing the question.

On a slow connection, the thumbnail may tuck away while the upload is still in progress. It retracts when the page *starts* receiving that image. Check the attachment area for progress. If the result is uncertain, Riftlet keeps a local record and leaves the decision to you.

If you switch between several conversations, how do you keep track of which picture belongs in which draft?

## Captions

**Video**

A close-up of the desktop tray as a saved screenshot appears in Riftlet. The sample artwork is a tidal map.

**Still**

This is how much of the edge the tray uses with screenshots waiting. The original files stay where macOS saved them.

## Project link

The Public Beta runs on Apple silicon and Intel Macs with macOS 13 or later. [Download and setup](https://riftlet.com/)

## Follow-up answers

**Why does it ask to control Chrome?**

After you choose an image, Riftlet uses Chrome automation to hand it to the current draft. Allow the macOS Automation request and enable “Allow JavaScript from Apple Events” in Chrome's View → Developer menu. Local collection and history work with the Chrome integration off.

**Has anyone checked adding two images to one draft?**

On build 18, two distinct screenshots reached the same real ChatGPT draft. The existing text and attachment stayed in place, and the message was left unsent. Build 20 carries forward that attachment code. The launch footage covers the desktop tray.

**Does every screenshot leave my Mac?**

The copies and history live on the Mac. Clicking a thumbnail hands that selected image to ChatGPT.

<p align="center">
  <img src="Sources/Wookey/Resources/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png" width="112" alt="Wookey app icon">
</p>

# Wookey

**Find apps and links, retrieve clipboard items and files, and run recurring tasks with a shortcut.** Wookey is a free, open-source macOS app for Apple Silicon and Intel Macs running macOS 14 or later. You can get started without a Wookey account.

[Preview releases](https://github.com/movvgli/Wookey/releases) · [Stable release](https://github.com/movvgli/Wookey/releases/latest) · [Website](https://movvgli.github.io/Wookey/) · [한국어](README.md)

## What you can do

| Feature | How it works |
| --- | --- |
| Quick search | Press **Option–Space** to find installed apps, saved links, templates, and workflows. Press Return to open or run the selection, or **Command–Return** to search the web in your default browser. In **Settings → General**, choose Google, Naver, Daum, or Nate. You can also enter web addresses, calculate, and convert currencies. |
| Apps and links | Assign shortcuts to your favorite apps and links. Give links and workflows multiple comma-separated search keywords. |
| Clipboard and drawer | Copy an earlier item from clipboard history. Shake the pointer twice while dragging a file to open the drawer. Open saved items later or drag them into another app. |
| Templates | Save phrases with formatting, links, lists, and inline images. Copy them from search or paste them as part of a workflow. |
| Workflows | Combine apps, links, files, template pastes, Return keystrokes, delays, and window layouts in a sequence. Run workflows with a global shortcut, from the menu bar, or from Apple Shortcuts. |
| Window layouts | Save the monitor and screen region for each app window. Restore layouts directly with a shortcut or include them in a workflow. |
| Appearance | Choose white, yellow, sky blue, brown, or dark. Pick Wookey and Banana or Sharkey and Coral, then choose 3D or Fluffy icons independently. |

## Download and get started

The [stable release](https://github.com/movvgli/Wookey/releases/latest) is Developer ID–signed and notarized by Apple. Older releases use the names **Monkey** and **Wikey**.

The features above describe the [preview releases](https://github.com/movvgli/Wookey/releases). To try them, download a Wookey DMG marked **Pre-release** near the top of the list. Preview builds are not notarized by Apple and are distributed separately from stable in-app updates.

1. Open the DMG and move the app to **Applications**.
2. Launch the app and press **Option–Space** to find a familiar app.
3. To chain multiple actions, create a new workflow and choose the option to combine actions.

Automated pasting, keystrokes, and window placement require **Accessibility** permission. Two-step shortcuts also require **Input Monitoring**. [Installation, permissions, and updates](docs/INSTALL.md)

## Data storage

Settings, templates, clipboard history, and drawer items are stored on your Mac by default. Optional iCloud sync can store workflows, templates, shortcuts, window layouts, and copies of workflow attachments in a private iCloud Drive folder. Clipboard history and drawer items stay on your Mac. [Privacy and sync details](docs/PRIVACY.md)

## Development and contributing

Use Xcode and a Swift 6 toolchain. Regenerating the Xcode project requires XcodeGen.

```sh
swift test
./script/build_and_run.sh
```

[Contributing](CONTRIBUTING.md) · [Security](SECURITY.md) · [Distribution](docs/DISTRIBUTION.md) · [MIT license](LICENSE)

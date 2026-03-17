# Pin

<p align="center">
  <img src="pin-agent/Pin/Resources/Assets.xcassets/AppIcon.appiconset/pin-macOS-128x128@2x.png" width="128" height="128" alt="Pin App Icon">
</p>

<p align="center">
  <strong>Keep any window always on top on macOS</strong>
</p>

---

## 🎬 How it works

See Pin in action: [southflowpeak.com/pin](https://southflowpeak.com/pin)

## ✨ Features

- 🪟 **Pin Any Window** - Select any window and keep it always visible on top
- 🔍 **Adjustable Opacity** - Make pinned windows semi-transparent (10% - 100%) to see through them
- 📋 **Menu Bar Control** - Easily select and manage windows from the menu bar
- 🔔 **Auto Updates** - Built-in automatic updates via Sparkle

## 📥 Installation

### Download

👉 [**Download Pin v0.1.3**](https://github.com/southflowpeak/Pin/releases/download/v0.1.3/Pin-v0.1.3.zip)

### System Requirements

- macOS 14.0 (Sonoma) or later

### 🔐 Screen Recording Permission

Pin requires **Screen Recording** permission to function.

<p align="center">
  <img src="docs/images/screen-recording-dialog.png" width="400" alt="Screen Recording Permission Dialog">
</p>

On first launch, you'll see the dialog above. Click "Open System Settings" and enable Pin in the Privacy & Security settings.

<p align="center">
  <img src="docs/images/screen-recording-settings.png" width="400" alt="Screen Recording Settings">
</p>

#### 💡 Why is Screen Recording permission required?

Pin uses macOS's **ScreenCaptureKit API** to keep windows on top:

1. **SCStream** captures the target window's content in real-time
2. The captured frames are displayed using **AVSampleBufferDisplayLayer**
3. This layer is placed in a floating window set to `NSWindow.Level.floating`

This creates a "mirror window" that stays on top even when the original window is behind other windows. Since ScreenCaptureKit is used to capture window content, macOS requires Screen Recording permission.

## 🚀 Usage

1. Click the 📌 icon in the menu bar
2. Select "Pin Window..." and choose the window you want to pin
3. To unpin, click the pin icon on the top-left of the mirror window, or select "Unpin" from the menu

## 📄 License

MIT License

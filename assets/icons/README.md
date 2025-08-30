# App Icons and Assets

This directory contains the app icons and splash screen assets for the Electricity Monitor Pro app.

## Required Files

### App Icon
- **File**: `app_icon.png`
- **Size**: 1024x1024 pixels (recommended)
- **Format**: PNG with transparent background
- **Description**: Main app icon used for launcher, notifications, etc.

### Splash Screen Icon
- **File**: `splash_icon.png`
- **Size**: 512x512 pixels (recommended)
- **Format**: PNG with transparent background
- **Description**: Icon displayed on the splash screen

## Icon Specifications

### Android
- **Adaptive Icons**: Supported (Android 8.0+)
- **Foreground**: App icon with transparent background
- **Background**: Can be solid color or gradient
- **Sizes Generated**: 48x48, 72x72, 96x96, 144x144, 192x192, 512x512

### iOS
- **Sizes Generated**: 20x20, 29x29, 40x40, 60x60, 76x76, 83.5x83.5, 1024x1024
- **Format**: PNG with appropriate transparency

### Web
- **Sizes Generated**: 192x192, 512x512 (PWA icons)
- **Background**: White (#ffffff)
- **Theme Color**: Blue (#007bff)

## Generation

After adding the icon files, run the following commands:

```bash
# Generate app icons
flutter pub run flutter_launcher_icons

# Generate splash screen
flutter pub run flutter_native_splash:create
```

## Branding Guidelines

- **Primary Color**: Blue (#007bff)
- **Secondary Color**: Green (#28a745)
- **Accent Color**: Orange (#fd7e14)
- **Background**: White (#ffffff) / Dark (#1a1a1a)

## Notes

- All icons should be designed with the electricity monitoring theme
- Consider using lightning bolt or meter symbols in the design
- Ensure good contrast and readability at small sizes
- Test icons on different backgrounds (light/dark themes)
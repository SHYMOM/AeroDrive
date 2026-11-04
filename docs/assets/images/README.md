# AeroDrive Website Image Assets Guide

This directory holds the images and mockups displayed on the AeroDrive website (`website/index.html`).

All current graphics are high-fidelity SVG mockups crafted with the exact visual language of AeroDrive (Obsidian dark theme `#090D16`, Cyan accent `#00D2FF`, Emerald `#10B981`, and Flutter glassmorphism).

You can use the website immediately with these high-resolution SVGs, or easily replace any of them with your own real screenshots from the Windows or Android app!

---

## Replaceable Image Inventory

| File Name | HTML Location / Section | Recommended Size | Format | Description |
| :--- | :--- | :--- | :--- | :--- |
| `logo.svg` | Navbar & Footer (`#nav-logo`, `#footer-logo`) | 48×48 px or SVG | `.svg` or `.png` | AeroDrive official aerodynamic wing & shield emblem |
| `hero-preview.svg` | Hero Section (`#hero-img`) | 1200×750 px | `.png`, `.webp`, or `.svg` | Main application window mockup showing drive navigation & live uploads |
| `drive-preview.svg` | Features Tab 1 (`#drive-img`) | 1000×640 px | `.png`, `.webp`, or `.svg` | File Explorer view with AES-256 badges and inspector panel |
| `gallery-preview.svg` | Features Tab 2 (`#gallery-img`) | 1000×640 px | `.png`, `.webp`, or `.svg` | Smart Gallery with local face recognition, memories, and photos |
| `stream-preview.svg` | Features Tab 3 (`#stream-img`) | 1000×640 px | `.png`, `.webp`, or `.svg` | 4K media player scrubbing through multi-gigabyte video without download |
| `vault-preview.svg` | Features Tab 4 (`#vault-img`) | 1000×640 px | `.png`, `.webp`, or `.svg` | Cryptographic Vault with Argon2id, BIP-39 recovery phrase & striping |

---

## How to Replace with Your Custom Screenshots

1. Take a screenshot of your running AeroDrive app (e.g. using `Win + Shift + S` on Windows).
2. Save your screenshot inside this directory: `website/assets/images/`.
   - **Option A (Instant swap)**: Name your screenshot with the exact existing file name (e.g. `hero-preview.png`), then in `website/index.html` change `.svg` to `.png`.
   - **Option B (Custom name)**: Name it e.g. `my-screenshot.png`. Open `website/index.html`, find the corresponding marked comment:
     ```html
     <!-- IMAGE PLACEHOLDER: Hero Application Screenshot -->
     <img id="hero-img" src="assets/images/hero-preview.svg" alt="AeroDrive UI" ... />
     ```
     Change `src="assets/images/hero-preview.svg"` to `src="assets/images/my-screenshot.png"`.

3. Refresh `website/index.html` in your browser.

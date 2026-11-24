# Wookey privacy and sync

Wookey works without a Wookey account and includes no analytics or advertising SDK. Workflows, templates, window layouts, clipboard history, and drawer files and links are stored on your Mac by default.

- Clipboard history is on by default. It keeps up to 500 entries and 1 GB, removing the oldest entries first. The drawer copies files up to 2 GB each and saves web links with their titles. You can set retention periods and turn off clipboard history in Settings. Wookey never syncs either history through iCloud.
- Wookey uses Accessibility for actions you initiate, including pasting and placing windows. Input Monitoring supports keyboard shortcuts that need to read a second keystroke or the Hyper key. Wookey does not transmit recorded keystrokes or clipboard history.
- Update checks contact the public GitHub update feed without sending your workflows, templates, or clipboard. Web search sends your query to Google through your browser. Currency conversion downloads public European Central Bank rates and calculates the result on your Mac.

## Optional iCloud sync

Sync is off by default. When you turn it on, choose the same private iCloud Drive folder on each Mac. Wookey stores shortcuts, workflows, templates, window layouts, and included attachments in that folder. Attachments are limited to 20 MB each and backup data to 50 MB. Anyone with access to the folder can read its backups. The Mac's permissions, login preferences, update preferences, and local history stay on that Mac.

When edits conflict, Wookey keeps both versions so you can choose which to use. Local recovery backups are kept for 30 days. A successful folder check confirms only that this Mac accessed the folder. Apple controls when changes arrive on other Macs.

## Download site

The site's demo uses fictional data. The site saves your language and light or dark mode choices in your browser and works when storage is blocked. Download and documentation links open GitHub.

[한국어 개인정보 안내](PRIVACY.md)

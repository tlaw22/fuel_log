# Fuel Log

A Flutter app for tracking fuel fill-ups, spending, totals, and fuel efficiency
on Android and Windows.

Demo of app available on YouTube.
[Watch the demo video - LINK](https://youtube.com/shorts/qNGNHvHNSpI?si=G2GmWQhQoJeuR-hz)

## Main sections

The home screen uses one carousel with these sections:

- **Log** - Add, edit, delete, and review fill-up records.
- **Totals** - Review all-time spending, monthly totals, weekly totals, fuel
  volume, distance, and efficiency.
- **Graphs** - Review monthly distance and fuel-efficiency charts, and set a
  monthly budget.
- **Photos** - Browse pump photos previously saved on Android.

Use the carousel labels or left/right arrows to move between sections.

## Theme

The AppBar theme icon switches between the dark theme and the light theme. The
selected theme is saved locally and restored the next time the app starts.

## Pump photos (Android)

From the new-fill-up dialog, select the camera icon to take a pump photo.
Before saving, the app displays a preview with **Save** and **Discard** options.
Saved photos are stored in:

`Documents/fuel-logs`

Open the **Photos** carousel section to view saved photos in a grid or open one
photo at a time. Opening a photo includes a delete button; the app asks for
confirmation before permanently deleting the selected photo.

Pump-photo capture and the saved gallery remain available on Android.
Desktop builds can browse an image folder starting at Pictures, and Web builds
can select pictures from the browser file picker. Selected desktop and Web
images are viewed for the current session and are not copied into FuelLog.

## CSV data

The menu in the left side of the AppBar provides:

- **Load CSV** - Pick a FuelLog CSV file and replace the current fill-up data
  after confirmation.
- **Save CSV** - Export the chronological fuel log to a CSV file.
- **Share CSV backup** - Open the Android share dialog. Select Google Drive or
  another backup destination to save the exported CSV.
- **About** - Read this README from the app.
- **Reports** - Generate a plain-text snapshot of the fuel log. Reports appear
  in a list and open in a readable bottom sheet with download and share
  actions; Web reports stay in browser storage and can be downloaded or opened
  in the default mail app, while Android reports are saved in Documents and
  shared with the system share sheet.
- **Wipe Data** - After confirmation, permanently remove saved fill-ups,
  monthly budget data, generated reports, and pump photos. CSV backups can
  restore fill-ups only; monthly values, reports, and photos are not included
  in CSV backups.

CSV files include fill-up date, odometer, price, amount, total cost, distance
since the previous fill-up, and efficiency when available.

On Android, saved CSV files are placed in the device's Documents folder.
Desktop builds use the system save and file-picker dialogs.

## Export

Use **Save CSV** in the AppBar menu to choose a destination in the system
save-file dialog.

## Graphs

The Graphs page saves monthly gross income, insurance, and car payments on this
device. Its travel-expense comparison includes fuel purchases from the log plus
the saved insurance and car payments, compared with the previous calendar
month. Missing previous-month values are shown as zero.

## Nearby sync (Android)

Open **Sync nearby** on both Android phones. Choose **Sender** on the phone
whose log should be transferred and **Receiver** on the other phone, then
connect and confirm with **Send log** and **Receive log**. Data travels only
from Sender to Receiver; the Receiver merges the received entries and
deletions, with the most recently edited version winning when entries conflict.
Nearby discovery may request Bluetooth, nearby-device, and (on some Android
versions) location permissions. Location/GPS must also be enabled; latest-edit
conflict resolution relies on the phones' clocks being reasonably accurate.

Nearby sync uses Bluetooth/Wi-Fi peer connectivity and requires both phones to
be nearby with the app open. It is not NFC or cloud sync.

Your log stays on this device unless you explicitly use Nearby Sync or export
or share a CSV backup.

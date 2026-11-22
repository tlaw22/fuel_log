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

Pump-photo capture and gallery management require Android. Windows and other
supported desktop previews display a platform-unavailable message.

## CSV data

The menu in the left side of the AppBar provides:

- **Load CSV** - Pick a FuelLog CSV file and replace the current fill-up data
  after confirmation.
- **Save CSV** - Export the chronological fuel log to a CSV file.
- **Share CSV backup** - Open the Android share dialog. Select Google Drive or
  another backup destination to save the exported CSV.
- **About** - Read this README from the app.

The **Totals** section also contains direct **Export CSV** and **Load CSV**
buttons. CSV files include fill-up date, odometer, price, amount, total cost,
distance since the previous fill-up, and efficiency when available.

On Android, saved CSV files are placed in the device's Documents folder.
Desktop builds use the system save and file-picker dialogs.

## Export

On the Totals tab, select **Export CSV** and choose a destination in the system
save-file dialog.

## Graphs

The Graphs page saves monthly gross income, insurance, and car payments on this
device. Its travel-expense comparison includes fuel purchases from the log plus
the saved insurance and car payments, compared with the previous calendar
month. Missing previous-month values are shown as zero.

## Nearby sync (Android)

Open **Sync nearby** on both Android phones. Connect one phone to the other,
then select **Sync log** on both phones. The app merges entries and deletions;
the most recently edited version wins when both phones have the same entry.
Both users must confirm before log data is sent. Nearby discovery may request
Bluetooth, nearby-device, and (on some Android versions) location permissions.
Location/GPS must also be enabled; latest-edit conflict resolution relies on
the phones' clocks being reasonably accurate.

Nearby sync uses Bluetooth/Wi-Fi peer connectivity and requires both phones to
be nearby with the app open. It is not NFC or cloud sync.

# Fuel Log

A Flutter app for tracking fuel fill-ups, spending, totals, and fuel efficiency
on Android and Windows.

Demo of app available:

[ LINK](http://discopro.cc/apps/fuelup/)

## Main sections

The home screen uses one carousel with these sections:

- **Log** - Add, edit, delete, and review fill-up records. Entries with
  matching odometer readings are marked **DUPLICATE**. Pressing **Save** on
  a new fill-up plays a coin-drop sound. Use the **MUTE** selector in the
  new-fill-up form to turn the sound off or on; the setting is remembered.
- **Totals** - Review all-time spending, monthly totals, weekly totals, fuel
  volume, distance, and efficiency.
- **Charts** - Review spending, distance, fuel efficiency, and travel expenses,
  and set a monthly budget.
- **Photos** - Browse pump photos previously saved on Android.
- **Lunch** - Record restaurant purchases, set a recurring daily lunch budget,
  and review daily, Monday-to-Sunday weekly, and monthly spending. Use the
  **Add lunch** floating button to enter a purchase. The daily pie shows
  spending against the budget; the custom chart compares food spending by
  period or restaurant, or the daily budget and remaining amount. Chart
  selections are remembered locally. Weekly
  totals include the whole week even when it crosses a month boundary; each
  monthly card shows only the days in that month. **Import lunch CSV** replaces
  lunch entries after confirmation; **Export lunch CSV** saves them separately
  from fuel data, including the restaurant, date and time, and price. Select
  **Other restaurant** to enter a new place; it is added to future suggestions.
  Native apps keep the editable `FuelLog/lunch_restaurants.csv` in the app
  documents directory (Android's app directory is private, so export it to
  edit externally). On the web, the restaurant list is saved in browser storage.
  **Import restaurants CSV** and **Export restaurants CSV** let you edit or
  transfer that list; importing replaces the list after confirmation.

The About and Photos pages link to downloads for other platforms.

Use the carousel labels or left/right arrows to move between sections.
At startup, a spinner appears on a white background while local data loads.
On the Web, it appears before Flutter finishes initializing.
On Log, Totals, Charts, and Photos, sections reveal from top to bottom at
half-second intervals each time the page is opened. Reduced-motion settings
show the content immediately.

The **Include lunch** selector at the bottom of Totals and Charts is shared
between both pages, remembered locally, and initially off. When enabled,
Totals separates fuel, lunch, and combined spending for each month and week,
including periods with lunch but no fill-ups; weeks are split at month
boundaries within the monthly cards. On Charts, the monthly budget
pie separates fuel, remaining budget, and lunch; if spending exceeds the
budget, the pie shows each purchase category's share of actual spending.
The month comparison includes each month's lunch in that month's total. The
custom chart adds this month's lunch as a third slice; selected amounts may
overlap. Its remaining-budget value also accounts for lunch. Fuel volume,
distance, and efficiency remain fuel-only. Fuel CSV
exports, reports, and fill-up notifications are unchanged.
Next to the AppBar menu, this month's spending shows fuel and, when enabled,
lunch. If lunch data cannot be loaded, the combined total is unavailable.

## Theme

The AppBar theme icon switches between dark and light modes. The palette icon
offers four choices for the active mode, including Coastal Blues in dark mode
and Summer Sunset in light mode. The Settings page also provides both controls.
The mode and each mode's selected palette are saved locally and restored the
next time the app starts.
Settings also adjusts app text from 80% to 200% of the device text size in
10% steps. A previously saved 60% setting is displayed at 80%.
Theme-colored background bubbles can also be disabled in Settings.
Both preferences are saved locally; reduced-motion settings pause bubble motion.

## Pump photos (Android)

From the new-fill-up dialog, select the camera icon to take a pump photo.
Before saving, the app displays a preview with **Save** and **Discard** options.
Saved photos are stored in:

`Documents/fuel-logs`

Open the **Photos** carousel section to view saved photos in a grid or open one
photo at a time. Opening a photo includes a delete button; the app asks for
confirmation before permanently deleting the selected photo.

Pump-photo capture and the saved gallery remain available on Android. Windows
and Web show an **Android Only Feature** notice on the Photos page. Other
desktop and iOS photo browsing behavior remains unchanged; selected external
images are viewed for the current session and are not copied into FuelLog.

## CSV data

The menu in the left side of the AppBar provides:

- **Load CSV** - Pick a FuelLog CSV file and replace the current fill-up data
  after confirmation.
- **Save CSV** - Export the chronological fuel log to a CSV file.
- **Share CSV backup** - Open the Android share dialog, or save a CSV backup
  with the Windows save dialog or Web browser download.
- **About** - Read this README from the app.
- **Reports** - Generate a plain-text snapshot of the fuel log. Reports appear
  in a list and open in a readable bottom sheet with download, share, and copy
  actions; Web reports stay in browser storage and can be downloaded or opened
  in the default mail app, while Android reports are saved in Documents and
  shared with the system share sheet. Reports include monthly summaries for up
  to the two most recent months, plus full fill-up details.
  Browser clipboard access may require HTTPS or localhost and permission.
- **Wipe Data** - After confirmation, permanently remove saved fill-ups,
  monthly budget data, lunch entries, budget and chart selections, generated
  reports, and pump photos. CSV backups can restore fill-ups only; monthly
  values, lunch data, reports, and photos are not included in CSV backups.

CSV files include fill-up date, odometer, price, amount, total cost, distance
since the previous fill-up, and efficiency when available.

Lunch records and the lunch budget are stored locally on this device. They
are separate from fuel reports, CSV import/export, and Bluetooth sync.

On Android, saved CSV files are placed in the device's Documents folder.
Windows uses the system save and file-picker dialogs. Web downloads exported
CSVs through the browser.

## Export

Use **Save CSV** in the AppBar menu to choose a destination in the system
save-file dialog.

## Charts

The Charts page saves monthly gross income, insurance, and car payments on this
device. Its travel-expense comparison includes fuel purchases from the log plus
the saved insurance and car payments, compared with the previous calendar
month. Missing previous-month values are shown as zero. The monthly comparison
also shows the distance traveled this month. Each pie shows the
percentages of the two colored portions, in the same order as the figures to
its left. Spending over budget fills the pie; the actual over-budget amount
and monthly budget percentage are shown separately. The bottom **Custom Chart**
compares any two financial amounts chosen from its dropdowns, and remembers
those selections. A missing budget or two zero amounts show "No data";
negative amounts show "Negative amount" instead of a percentage.


Saving a fill-up posts a custom-chart notification on Android, Windows, and
supported browsers, with the amount purchased and total cost in the notification
title.


Android displays the comparison pie; browser notifications include it when
supported. Windows shows a pie for lunch and a text summary for fill-ups. Browsers ask
for permission on Save and require HTTPS or localhost. Windows uses system
notification settings rather than an app permission prompt. Android may also
request notification permission. Notifications can be disabled in system or
browser settings. The app attempts to remove its notifications when data is
wiped; Windows may restrict notification removal for unpackaged apps.
If a browser or Windows notification update fails after saving fuel or lunch,
the app shows a snackbar; the saved entry remains available.

## Bluetooth file sharing (Android)

Pair both Android phones with each other in Android Bluetooth settings. Open
**Bluetooth Share** in FuelLog on both phones and select the other phone from
the paired-phone list. The red status button confirms the selected pairing.

Open **Begin Bluetooth File Sharing** on both phones. Choose **Receiver** on one
phone and tap **Wait for sender** first. On the other phone choose **Sender**
and tap **Connect and send log**. The Receiver merges the received entries and
deletions; the most recently edited version wins when entries conflict.

Your log stays on this device unless you explicitly use Bluetooth sharing or
export or share a CSV backup.

<<<<<<< HEAD
## Install the web app

On phones, Chrome, Edge, and Safari can show an invitation to install FuelLog.
Use the browser's install prompt when available, or follow the Add to Home
Screen instructions. The invitation can be dismissed for the browser session
and does not appear when FuelLog is running as an installed app. Installation
requires HTTPS or localhost.

Saved data may not carry over to the installed app. Export a CSV backup first;
CSV backups do not include all app data.

## App icons

The launcher icons are generated from `lib/img/app-icon.jpg` with
`dart run flutter_launcher_icons`. Linux bundles the generated 512-pixel web
icon for its window; desktop launcher integration depends on the Linux package
and desktop environment.
=======
>>>>>>> be3b6f082786ee613d663888e7d3c721101a9e48

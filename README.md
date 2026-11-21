# Fuel Log

A Flutter app for tracking fuel fill-ups, spending, and fuel efficiency. Local networking and no other data sharing.

## Export

On the Totals tab, select **Export CSV** and choose a destination in the system
save-file dialog.

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

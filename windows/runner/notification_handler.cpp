#include "notification_handler.h"

#include <windows.h>
#include <winrt/Windows.Data.Xml.Dom.h>
#include <winrt/Windows.UI.Notifications.h>

#include <flutter/standard_method_codec.h>

#include <stdexcept>
#include <string>

namespace {
constexpr wchar_t kAppId[] = L"io.github.tlaw22.FuelLog";
constexpr wchar_t kTag[] = L"custom-chart";
constexpr wchar_t kGroup[] = L"fuel-log";

void RegisterAppIdentity() {
  HKEY key;
  const wchar_t path[] =
      L"Software\\Classes\\AppUserModelId\\io.github.tlaw22.FuelLog";
  auto status = RegCreateKeyExW(HKEY_CURRENT_USER, path, 0, nullptr, 0,
                               KEY_SET_VALUE, nullptr, &key, nullptr);
  if (status != ERROR_SUCCESS) {
    throw winrt::hresult_error(HRESULT_FROM_WIN32(status));
  }
  const wchar_t name[] = L"FuelLog";
  status = RegSetValueExW(key, L"DisplayName", 0, REG_SZ,
                          reinterpret_cast<const BYTE*>(name), sizeof(name));
  RegCloseKey(key);
  if (status != ERROR_SUCCESS) {
    throw winrt::hresult_error(HRESULT_FROM_WIN32(status));
  }
}

std::string GetText(const flutter::EncodableMap& values, const char* key) {
  auto item = values.find(flutter::EncodableValue(key));
  if (item == values.end()) {
    throw std::invalid_argument("Missing notification field.");
  }
  const auto* text = std::get_if<std::string>(&item->second);
  if (!text) throw std::invalid_argument("Invalid notification field.");
  return *text;
}

void ShowNotification(const flutter::EncodableMap& values) {
  using namespace winrt::Windows::Data::Xml::Dom;
  using namespace winrt::Windows::UI::Notifications;

  const auto first = GetText(values, "firstLabel") + ": " +
                     GetText(values, "firstAmount");
  const auto second = GetText(values, "secondLabel") + ": " +
                      GetText(values, "secondAmount");
  const auto title = GetText(values, "title");
  const auto fill_up = GetText(values, "fillUp");
  RegisterAppIdentity();
  const auto notifier = ToastNotificationManager::CreateToastNotifier(kAppId);
  if (notifier.Setting() != NotificationSetting::Enabled) {
    throw std::runtime_error(
        "Notifications are disabled in Windows notification settings.");
  }
  XmlDocument xml;
  xml.LoadXml(L"<toast><visual><binding template=\"ToastGeneric\">"
              L"<text></text><text></text><text></text>"
              L"</binding></visual></toast>");
  const auto text = xml.GetElementsByTagName(L"text");
  text.Item(0).InnerText(winrt::to_hstring(title));
  text.Item(1).InnerText(winrt::to_hstring(fill_up));
  text.Item(2).InnerText(winrt::to_hstring(first + " | " + second));
  ToastNotification notification(xml);
  notification.Tag(kTag);
  notification.Group(kGroup);
  notifier.Show(notification);
}
}  // namespace

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
CreateNotificationChannel(flutter::BinaryMessenger* messenger) {
  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "io.github.tlaw22.fuellog/windows_notification",
      &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler(
      [](const auto& call, auto result) {
        try {
          if (call.method_name() == "show") {
            const auto* values =
                std::get_if<flutter::EncodableMap>(call.arguments());
            if (!values) throw std::invalid_argument("Invalid notification data.");
            ShowNotification(*values);
            result->Success();
          } else if (call.method_name() == "cancel") {
            winrt::Windows::UI::Notifications::ToastNotificationManager::
                History().Remove(kTag, kGroup, kAppId);
            result->Success();
          } else {
            result->NotImplemented();
          }
        } catch (const winrt::hresult_error& error) {
          result->Error("notification_failed", winrt::to_string(error.message()));
        } catch (const std::exception& error) {
          result->Error("notification_failed", error.what());
        }
      });
  return channel;
}

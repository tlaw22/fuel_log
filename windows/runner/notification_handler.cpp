#include "notification_handler.h"

#include <windows.h>
#include <gdiplus.h>
#include <shlwapi.h>
#include <winrt/Windows.Data.Xml.Dom.h>
#include <winrt/Windows.UI.Notifications.h>

#include <flutter/standard_method_codec.h>

#include <cmath>
#include <filesystem>
#include <optional>
#include <stdexcept>
#include <string>

namespace {
constexpr wchar_t kAppId[] = L"io.github.tlaw22.FuelLog";
constexpr wchar_t kTag[] = L"custom-chart";
constexpr wchar_t kLunchTag[] = L"lunch-budget";
constexpr wchar_t kGroup[] = L"fuel-log";

std::filesystem::path LunchImagePath() {
  return std::filesystem::temp_directory_path() / L"fuel-log-lunch-chart.png";
}

std::optional<double> GetAmount(const flutter::EncodableMap& values,
                                const char* key) {
  const auto item = values.find(flutter::EncodableValue(key));
  if (item == values.end()) throw std::invalid_argument("Missing chart amount.");
  if (std::holds_alternative<std::monostate>(item->second)) return std::nullopt;
  const auto* amount = std::get_if<double>(&item->second);
  if (!amount || !std::isfinite(*amount) || *amount < 0) {
    throw std::invalid_argument("Invalid chart amount.");
  }
  return *amount;
}

std::wstring DrawLunchChart(const flutter::EncodableMap& values) {
  const auto spent = GetAmount(values, "firstTotal");
  const auto remaining = GetAmount(values, "secondTotal");
  const double total = spent && remaining ? *spent + *remaining : 0;
  const double share = total > 0 ? *spent / total : 0;

  Gdiplus::GdiplusStartupInput input;
  ULONG_PTR token;
  if (Gdiplus::GdiplusStartup(&token, &input, nullptr) != Gdiplus::Ok) {
    throw std::runtime_error("Could not initialize the lunch chart.");
  }
  struct GdiShutdown {
    ULONG_PTR token;
    ~GdiShutdown() { Gdiplus::GdiplusShutdown(token); }
  } shutdown{token};

  Gdiplus::Bitmap image(600, 240, PixelFormat32bppARGB);
  {
    Gdiplus::Graphics graphics(&image);
    graphics.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
    graphics.Clear(Gdiplus::Color(255, 255, 255, 255));
    Gdiplus::SolidBrush base(total > 0 ? Gdiplus::Color(255, 0, 53, 102)
                                       : Gdiplus::Color(255, 204, 204, 204));
    Gdiplus::SolidBrush filled(Gdiplus::Color(255, 255, 195, 0));
    graphics.FillEllipse(&base, 208, 28, 184, 184);
    if (share > 0) {
      graphics.FillPie(&filled, 208, 28, 184, 184, -90.0f,
                       static_cast<float>(share * 360));
    }
    Gdiplus::SolidBrush white(Gdiplus::Color(255, 255, 255, 255));
    graphics.FillRectangle(&white, 229, 103, 142, 34);
    Gdiplus::SolidBrush black(Gdiplus::Color(255, 0, 0, 0));
    Gdiplus::FontFamily family(L"Segoe UI");
    Gdiplus::Font font(&family, 18);
    Gdiplus::StringFormat format;
    format.SetAlignment(Gdiplus::StringAlignmentCenter);
    const auto percent = static_cast<int>(std::round(share * 100));
    const auto label = total == 0 ? std::wstring(L"No data")
                                  : std::to_wstring(percent) + L"% / " +
                                        std::to_wstring(100 - percent) + L"%";
    Gdiplus::RectF label_rect(229, 105, 142, 30);
    graphics.DrawString(label.c_str(), -1, &font, label_rect, &format, &black);
  }

  CLSID png;
  if (FAILED(CLSIDFromString(L"{557CF406-1A04-11D3-9A73-0000F81EF32E}", &png)) ||
      image.Save(LunchImagePath().c_str(), &png, nullptr) != Gdiplus::Ok) {
    throw std::runtime_error("Could not save the lunch chart image.");
  }
  wchar_t url[32768];
  DWORD length = static_cast<DWORD>(std::size(url));
  const auto result = UrlCreateFromPathW(LunchImagePath().c_str(), url, &length, 0);
  if (FAILED(result)) throw winrt::hresult_error(result);
  return url;
}

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

void ShowNotification(const flutter::EncodableMap& values, bool lunch = false) {
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
  if (lunch) {
    const auto image = xml.CreateElement(L"image");
    image.SetAttribute(L"placement", L"hero");
    image.SetAttribute(L"src", DrawLunchChart(values));
    xml.GetElementsByTagName(L"binding").Item(0).AppendChild(image);
  }
  ToastNotification notification(xml);
  notification.Tag(lunch ? kLunchTag : kTag);
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
          if (call.method_name() == "show" || call.method_name() == "showLunch") {
            const auto* values =
                std::get_if<flutter::EncodableMap>(call.arguments());
            if (!values) throw std::invalid_argument("Invalid notification data.");
            ShowNotification(*values, call.method_name() == "showLunch");
            result->Success();
          } else if (call.method_name() == "cancel") {
            winrt::Windows::UI::Notifications::ToastNotificationManager::
                History().Remove(kTag, kGroup, kAppId);
            result->Success();
          } else if (call.method_name() == "cancelLunch") {
            winrt::Windows::UI::Notifications::ToastNotificationManager::
                History().Remove(kLunchTag, kGroup, kAppId);
            std::filesystem::remove(LunchImagePath());
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

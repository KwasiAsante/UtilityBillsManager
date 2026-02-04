#include "flutter_window.h"

#include <flutter/event_channel.h>
#include <flutter/event_sink.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <memory>
#include <sstream>

#include <memory>

#include <optional>

#include "flutter/generated_plugin_registrant.h"

static std::string RunPdfToText(const std::string &filePath)
{
  std::string outputPath = filePath + ".txt";

  std::ostringstream cmd;
  cmd << "windows\\bin\\pdftotext.exe \"" << filePath << "\" \"" << outputPath << "\"";

  int result = system(cmd.str().c_str());
  if (result != 0)
    return "";

  std::ifstream file(outputPath);
  if (!file.is_open())
    return "";

  std::stringstream buffer;
  buffer << file.rdbuf();
  file.close();

  std::filesystem::remove(outputPath); // Clean up temp .txt

  return buffer.str();
}

FlutterWindow::FlutterWindow(const flutter::DartProject &project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate()
{
  if (!Win32Window::OnCreate())
  {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view())
  {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());

  flutter::MethodChannel<> channel(
      flutter_controller_->engine()->messenger(), "pdf_text",
      &flutter::StandardMethodCodec::GetInstance());

  channel.SetMethodCallHandler(
      [](const flutter::MethodCall<> &call,
         std::unique_ptr<flutter::MethodResult<>> result)
      {
        if (call.method_name() == "extractPdfText")
        {
          const auto *args = std::get_if<flutter::EncodableMap>(call.arguments());
          if (!args)
          {
            result->Error("Bad args", "Expected map");
            return;
          }

          auto it = args->find(flutter::EncodableValue("filePath"));
          if (it == args->end() || !std::holds_alternative<std::string>(it->second))
          {
            result->Error("Missing or invalid 'path'");
            return;
          }

          std::string path = std::get<std::string>(it->second);
          std::string text = RunPdfToText(path);

          result->Success(flutter::EncodableValue(text));
        }
        else
        {
          result->NotImplemented();
        }
      });

  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]()
                                                      { this->Show(); });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy()
{
  if (flutter_controller_)
  {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept
{
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_)
  {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result)
    {
      return *result;
    }
  }

  switch (message)
  {
  case WM_FONTCHANGE:
    flutter_controller_->engine()->ReloadSystemFonts();
    break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
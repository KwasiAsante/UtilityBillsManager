#include "pdf_text_plugin.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <windows.h>
#include <fstream>
#include <iostream>
#include <memory>
#include <sstream>

namespace
{

  std::string RunPdftoText(const std::string &filePath)
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

  class PdfTextPlugin : public flutter::Plugin
  {
  public:
    static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar)
    {
      auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "pdf_text",
          &flutter::StandardMethodCodec::GetInstance());

      auto plugin = std::make_unique<PdfTextPlugin>();

      channel->SetMethodCallHandler(
          [plugin_pointer = plugin.get()](const auto &call, auto result)
          {
            plugin_pointer->HandleMethodCall(call, std::move(result));
          });

      registrar->AddPlugin(std::move(plugin));
    }

    static void RegisterWithEngine(flutter::FlutterEngine *engine)
    {
      auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "pdf_text",
          &flutter::StandardMethodCodec::GetInstance());

      auto plugin = std::make_unique<PdfTextPlugin>();

      channel->SetMethodCallHandler(
          [plugin_pointer = plugin.get()](const auto &call, auto result)
          {
            plugin_pointer->HandleMethodCall(call, std::move(result));
          });

      registrar->AddPlugin(std::move(plugin));
    }

    void HandleMethodCall(const flutter::MethodCall<flutter::EncodableValue> &call,
                          std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result)
    {
      if (call.method_name() == "extractText")
      {
        const auto *args = std::get_if<flutter::EncodableMap>(call.arguments());
        if (!args)
        {
          result->Error("Bad args", "Expected map");
          return;
        }

        auto it = args->find(flutter::EncodableValue("path"));
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
    }
  };

} // namespace

void RegisterPdfPlugin(flutter::FlutterEngine *registrar)
{
  PdfTextPlugin::RegisterWithRegistrar(registrar);
}

void RegisterPdfPlugin(flutter::FlutterEngine *engine)
{
  PdfTextPlugin::RegisterWithEngine(engine);
}
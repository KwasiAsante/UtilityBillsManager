import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

class TrayManagerService with TrayListener {
  Future<void> init() async {
    trayManager.addListener(this);
    await trayManager.setIcon('assets/icon/utility_bills_manager_icon.ico');
    await trayManager.setToolTip('Utility Bills Manager');
    await trayManager.setContextMenu(Menu(items: [
      MenuItem(key: 'show', label: 'Show'),
      MenuItem.separator(),
      MenuItem(key: 'quit', label: 'Quit'),
    ]));
  }

  @override
  void onTrayIconMouseDown() => windowManager.show();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == 'show') windowManager.show();
    if (menuItem.key == 'quit') windowManager.destroy();
  }
}
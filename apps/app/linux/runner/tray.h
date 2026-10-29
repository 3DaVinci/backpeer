#ifndef RUNNER_TRAY_H_
#define RUNNER_TRAY_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

// Значок в трее (задача 5.6.2): AppIndicator / StatusNotifierItem через
// libayatana-appindicator3 или libappindicator3, загруженную dlopen —
// без зависимости сборки и без падения, если библиотеки нет.
//
// Канал `fs/tray` (FlStandardMethodCodec):
// - Dart → натив: `available` → bool (значок показан и его есть кому
//   отобразить); `setMenu` {status, items: [{id, label, enabled}]};
// - натив → Dart: `action` с id пункта (кроме `open` и `quit`, которые
//   натив выполняет сам: показать окно, выйти из приложения).

typedef struct _Tray Tray;

// Создаёт значок. `window` показывается по «Открыть окно»; `app` —
// завершается по «Выйти».
Tray* tray_new(GtkApplication* app, GtkWindow* window);

// Канал для движка `view` — после создания FlView.
void tray_attach(Tray* tray, FlView* view);

// Значок создан, и в сеансе есть кому его показать
// (org.kde.StatusNotifierWatcher: KDE, GNOME с расширением AppIndicator).
gboolean tray_available(Tray* tray);

void tray_free(Tray* tray);

#endif  // RUNNER_TRAY_H_

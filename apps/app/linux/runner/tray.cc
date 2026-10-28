#include "tray.h"

#include <dlfcn.h>

#include <cstring>

// Функции AppIndicator, которые нужны значку. Объявлены здесь, а не из
// заголовков: библиотека загружается при запуске, заголовки для сборки
// не нужны.
typedef void* (*IndicatorNew)(const gchar* id, const gchar* icon, int category);
typedef void (*IndicatorSetStatus)(void* indicator, int status);
typedef void (*IndicatorSetMenu)(void* indicator, GtkMenu* menu);
typedef void (*IndicatorSetThemePath)(void* indicator, const gchar* path);
typedef void (*IndicatorSetTitle)(void* indicator, const gchar* title);

// APP_INDICATOR_CATEGORY_APPLICATION_STATUS, APP_INDICATOR_STATUS_ACTIVE.
static const int kCategoryApplicationStatus = 0;
static const int kStatusActive = 1;

struct _Tray {
  GtkApplication* app;
  GtkWindow* window;
  void* library;
  void* indicator;
  IndicatorSetMenu set_menu;
  GtkWidget* menu;
  FlMethodChannel* channel;
  gboolean watcher;
};

// Папка значков рядом с программой: <бандл>/data/icons.
static gchar* icon_dir() {
  g_autofree gchar* exe = g_file_read_link("/proc/self/exe", nullptr);
  if (exe == nullptr) return nullptr;
  g_autofree gchar* dir = g_path_get_dirname(exe);
  return g_build_filename(dir, "data", "icons", nullptr);
}

// Есть ли в сеансе хост значков StatusNotifierItem.
static gboolean has_watcher() {
  g_autoptr(GError) error = nullptr;
  g_autoptr(GDBusConnection) bus =
      g_bus_get_sync(G_BUS_TYPE_SESSION, nullptr, &error);
  if (bus == nullptr) return FALSE;
  g_autoptr(GVariant) reply = g_dbus_connection_call_sync(
      bus, "org.freedesktop.DBus", "/org/freedesktop/DBus",
      "org.freedesktop.DBus", "NameHasOwner",
      g_variant_new("(s)", "org.kde.StatusNotifierWatcher"),
      G_VARIANT_TYPE("(b)"), G_DBUS_CALL_FLAGS_NONE, 1000, nullptr, &error);
  if (reply == nullptr) return FALSE;
  gboolean owned = FALSE;
  g_variant_get(reply, "(b)", &owned);
  return owned;
}

static void show_window(Tray* tray) {
  gtk_widget_show(GTK_WIDGET(tray->window));
  gtk_window_present(tray->window);
}

static void on_item(GtkMenuItem* item, gpointer user_data) {
  Tray* tray = static_cast<Tray*>(user_data);
  const gchar* id =
      static_cast<const gchar*>(g_object_get_data(G_OBJECT(item), "id"));
  if (g_strcmp0(id, "open") == 0) {
    show_window(tray);
    return;
  }
  if (g_strcmp0(id, "quit") == 0) {
    g_application_quit(G_APPLICATION(tray->app));
    return;
  }
  if (tray->channel != nullptr) {
    fl_method_channel_invoke_method(tray->channel, "action",
                                    fl_value_new_string(id), nullptr, nullptr,
                                    nullptr);
  }
}

static GtkWidget* add_item(Tray* tray, GtkWidget* menu, const gchar* id,
                           const gchar* label, gboolean enabled) {
  GtkWidget* item = gtk_menu_item_new_with_label(label);
  g_object_set_data_full(G_OBJECT(item), "id", g_strdup(id), g_free);
  gtk_widget_set_sensitive(item, enabled);
  g_signal_connect(item, "activate", G_CALLBACK(on_item), tray);
  gtk_menu_shell_append(GTK_MENU_SHELL(menu), item);
  gtk_widget_show(item);
  return item;
}

// Меню целиком заменяется новым: так проще, чем менять пункты на месте.
static void set_menu(Tray* tray, FlValue* args) {
  if (tray->indicator == nullptr) return;
  GtkWidget* menu = gtk_menu_new();
  FlValue* status = fl_value_lookup_string(args, "status");
  if (status != nullptr && fl_value_get_type(status) == FL_VALUE_TYPE_STRING) {
    add_item(tray, menu, "status", fl_value_get_string(status), FALSE);
    GtkWidget* separator = gtk_separator_menu_item_new();
    gtk_menu_shell_append(GTK_MENU_SHELL(menu), separator);
    gtk_widget_show(separator);
  }
  FlValue* items = fl_value_lookup_string(args, "items");
  if (items != nullptr && fl_value_get_type(items) == FL_VALUE_TYPE_LIST) {
    for (size_t i = 0; i < fl_value_get_length(items); i++) {
      FlValue* entry = fl_value_get_list_value(items, i);
      FlValue* id = fl_value_lookup_string(entry, "id");
      FlValue* label = fl_value_lookup_string(entry, "label");
      FlValue* enabled = fl_value_lookup_string(entry, "enabled");
      if (id == nullptr || label == nullptr) continue;
      if (g_strcmp0(fl_value_get_string(id), "-") == 0) {
        GtkWidget* separator = gtk_separator_menu_item_new();
        gtk_menu_shell_append(GTK_MENU_SHELL(menu), separator);
        gtk_widget_show(separator);
        continue;
      }
      add_item(tray, menu, fl_value_get_string(id),
               fl_value_get_string(label),
               enabled == nullptr || fl_value_get_bool(enabled));
    }
  }
  // Меню забирает индикатор (ref_sink), прежнее он отпускает сам.
  tray->set_menu(tray->indicator, GTK_MENU(menu));
  tray->menu = menu;
}

static void on_call(FlMethodChannel* channel, FlMethodCall* call,
                    gpointer user_data) {
  Tray* tray = static_cast<Tray*>(user_data);
  const gchar* method = fl_method_call_get_name(call);
  g_autoptr(FlMethodResponse) response = nullptr;
  if (strcmp(method, "available") == 0) {
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(
        fl_value_new_bool(tray_available(tray))));
  } else if (strcmp(method, "setMenu") == 0) {
    FlValue* args = fl_method_call_get_args(call);
    if (args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      set_menu(tray, args);
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(call, response, nullptr);
}

Tray* tray_new(GtkApplication* app, GtkWindow* window) {
  Tray* tray = g_new0(Tray, 1);
  tray->app = app;
  tray->window = window;
  const char* names[] = {"libayatana-appindicator3.so.1",
                         "libappindicator3.so.1"};
  for (const char* name : names) {
    tray->library = dlopen(name, RTLD_LAZY | RTLD_LOCAL);
    if (tray->library != nullptr) break;
  }
  if (tray->library == nullptr) return tray;
  auto create =
      reinterpret_cast<IndicatorNew>(dlsym(tray->library, "app_indicator_new"));
  auto set_status = reinterpret_cast<IndicatorSetStatus>(
      dlsym(tray->library, "app_indicator_set_status"));
  auto set_theme_path = reinterpret_cast<IndicatorSetThemePath>(
      dlsym(tray->library, "app_indicator_set_icon_theme_path"));
  auto set_title = reinterpret_cast<IndicatorSetTitle>(
      dlsym(tray->library, "app_indicator_set_title"));
  tray->set_menu = reinterpret_cast<IndicatorSetMenu>(
      dlsym(tray->library, "app_indicator_set_menu"));
  if (create == nullptr || set_status == nullptr || tray->set_menu == nullptr) {
    return tray;
  }
  tray->indicator =
      create(APPLICATION_ID, "file-storage-tray", kCategoryApplicationStatus);
  g_autofree gchar* icons = icon_dir();
  if (set_theme_path != nullptr && icons != nullptr) {
    set_theme_path(tray->indicator, icons);
  }
  if (set_title != nullptr) set_title(tray->indicator, "File Storage");
  set_status(tray->indicator, kStatusActive);
  // Пока Dart не прислал меню: без меню значок не показывается.
  GtkWidget* menu = gtk_menu_new();
  add_item(tray, menu, "open", "File Storage", TRUE);
  tray->set_menu(tray->indicator, GTK_MENU(menu));
  tray->menu = menu;
  tray->watcher = has_watcher();
  return tray;
}

void tray_attach(Tray* tray, FlView* view) {
  FlEngine* engine = fl_view_get_engine(view);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  tray->channel = fl_method_channel_new(fl_engine_get_binary_messenger(engine),
                                        "fs/tray", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(tray->channel, on_call, tray,
                                            nullptr);
}

gboolean tray_available(Tray* tray) {
  return tray != nullptr && tray->indicator != nullptr && tray->watcher;
}

void tray_free(Tray* tray) {
  if (tray == nullptr) return;
  g_clear_object(&tray->channel);
  if (tray->indicator != nullptr) g_object_unref(tray->indicator);
  // Библиотеку не выгружаем: на неё могут ссылаться типы GObject.
  g_free(tray);
}

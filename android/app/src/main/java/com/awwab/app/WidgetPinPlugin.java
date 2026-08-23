package com.awwab.app;

import android.appwidget.AppWidgetManager;
import android.content.ComponentName;
import android.content.Context;
import android.os.Build;

import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

// "إضافة الودجت للشاشة الرئيسية" بزر واحد (Phase 2) — بيستخدم
// AppWidgetManager.requestPinAppWidget الرسمية بدل ما نسيب المستخدم
// يدوّر يدويًا. لو الجهاز/الـLauncher مايدعمهاش، الواجهة (JS) بترجع
// لتعليمات الإضافة اليدوية (Bottom Sheet) — الـplugin ده بس بيقول
// "مدعومة ولا لأ" وبيبدأ الطلب، مفيش منطق fallback هنا.
@CapacitorPlugin(name = "WidgetPin")
public class WidgetPinPlugin extends Plugin {

    @PluginMethod
    public void isSupported(PluginCall call) {
        JSObject ret = new JSObject();
        ret.put("supported", pinSupported());
        call.resolve(ret);
    }

    @PluginMethod
    public void getWidgetCount(PluginCall call) {
        JSObject ret = new JSObject();
        ret.put("count", currentWidgetCount());
        call.resolve(ret);
    }

    @PluginMethod
    public void requestPin(PluginCall call) {
        if (!pinSupported()) {
            JSObject ret = new JSObject();
            ret.put("requested", false);
            call.resolve(ret);
            return;
        }
        Context context = getContext();
        AppWidgetManager manager = AppWidgetManager.getInstance(context);
        ComponentName provider = new ComponentName(context, AwwabWidgetProvider.class);
        boolean started = manager.requestPinAppWidget(provider, null, null);
        JSObject ret = new JSObject();
        ret.put("requested", started);
        call.resolve(ret);
    }

    private boolean pinSupported() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false;
        Context context = getContext();
        AppWidgetManager manager = AppWidgetManager.getInstance(context);
        return manager != null && manager.isRequestPinAppWidgetSupported();
    }

    private int currentWidgetCount() {
        Context context = getContext();
        AppWidgetManager manager = AppWidgetManager.getInstance(context);
        ComponentName provider = new ComponentName(context, AwwabWidgetProvider.class);
        int[] ids = manager.getAppWidgetIds(provider);
        return ids == null ? 0 : ids.length;
    }
}

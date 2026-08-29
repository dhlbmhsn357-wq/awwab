package com.awwab.app;

import android.appwidget.AppWidgetManager;
import android.content.ComponentName;
import android.content.Context;
import android.content.SharedPreferences;

import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

// الجسر بين صفحة الويب (index.html) والودجت النيتف — مسؤوليته الوحيدة:
// ياخد "لقطة" مختصرة من حالة اليوم (اتحسبت محليًا من IndexedDB جوه
// الـWebView) ويخزّنها في SharedPreferences مخصّصة للودجت، بعدين
// يطلب تحديث فوري للودجت. الودجت (AwwabWidgetProvider) بتقرا من
// الـSharedPreferences دي بس — أبدًا ماتكلّمش Supabase مباشرة.
@CapacitorPlugin(name = "WidgetBridge")
public class WidgetBridgePlugin extends Plugin {

    public static final String PREFS_NAME = "awwab_widget_prefs";

    @PluginMethod
    public void updateSnapshot(PluginCall call) {
        Context context = getContext();
        SharedPreferences prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE);
        SharedPreferences.Editor editor = prefs.edit();

        editor.putString("date", call.getString("date", ""));
        editor.putInt("completedCount", call.getInt("completedCount", 0));
        editor.putInt("totalCount", call.getInt("totalCount", 0));
        editor.putString("nextWorshipName", call.getString("nextWorshipName", ""));
        editor.putBoolean("nextIsPin", call.getBoolean("nextIsPin", false));
        editor.putBoolean("privacyMode", call.getBoolean("privacyMode", false));
        editor.putLong("updatedAt", System.currentTimeMillis());
        editor.apply();

        AppWidgetManager manager = AppWidgetManager.getInstance(context);
        ComponentName provider = new ComponentName(context, AwwabWidgetProvider.class);
        int[] widgetIds = manager.getAppWidgetIds(provider);
        if (widgetIds != null && widgetIds.length > 0) {
            AwwabWidgetProvider.updateAllWidgets(context, manager, widgetIds);
        }

        call.resolve();
    }
}

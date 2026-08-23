package com.awwab.app;

import android.app.PendingIntent;
import android.appwidget.AppWidgetManager;
import android.appwidget.AppWidgetProvider;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.net.Uri;
import android.widget.RemoteViews;

// ودجت الشاشة الرئيسية — للقراءة بس. مفيش أي تعديل بيانات ممكن يحصل
// من جوها؛ اللمسة الوحيدة المتاحة (الودجت كله) بتفتح التطبيق على
// تبويب "اليوم" عشان أي تسجيل عبادة يمر بشاشة التطبيق نفسها (بند 37
// من المتطلبات الأصلية: الأمان قبل السرعة). بتقرا بس من
// SharedPreferences اللي WidgetBridgePlugin بيحدّثها — أبدًا مالهاش
// اتصال مباشر بـSupabase.
public class AwwabWidgetProvider extends AppWidgetProvider {

    @Override
    public void onUpdate(Context context, AppWidgetManager appWidgetManager, int[] appWidgetIds) {
        updateAllWidgets(context, appWidgetManager, appWidgetIds);
    }

    public static void updateAllWidgets(Context context, AppWidgetManager appWidgetManager, int[] appWidgetIds) {
        for (int id : appWidgetIds) {
            updateWidget(context, appWidgetManager, id);
        }
    }

    private static void updateWidget(Context context, AppWidgetManager appWidgetManager, int appWidgetId) {
        SharedPreferences prefs = context.getSharedPreferences(WidgetBridgePlugin.PREFS_NAME, Context.MODE_PRIVATE);
        RemoteViews views = new RemoteViews(context.getPackageName(), R.layout.widget_awwab);

        long updatedAt = prefs.getLong("updatedAt", 0);
        boolean privacyMode = prefs.getBoolean("privacyMode", false);
        if (updatedAt == 0) {
            views.setTextViewText(R.id.widget_summary, context.getString(R.string.widget_no_data));
            views.setTextViewText(R.id.widget_next, context.getString(R.string.widget_open_hint));
        } else if (privacyMode) {
            // وضع الخصوصية (Phase 8) — مفيش أي رقم أو اسم عبادة ظاهر
            // على الشاشة الرئيسية، حتى لو حد تاني شايف الموبايل
            views.setTextViewText(R.id.widget_summary, context.getString(R.string.app_name));
            views.setTextViewText(R.id.widget_next, context.getString(R.string.widget_open_hint));
        } else {
            int completed = prefs.getInt("completedCount", 0);
            int total = prefs.getInt("totalCount", 0);
            String next = prefs.getString("nextWorshipName", "");

            views.setTextViewText(R.id.widget_summary, context.getString(R.string.widget_summary_format, completed, total));
            if (next != null && !next.isEmpty()) {
                views.setTextViewText(R.id.widget_next, context.getString(R.string.widget_next_format, next));
            } else if (total > 0) {
                views.setTextViewText(R.id.widget_next, context.getString(R.string.widget_all_done));
            } else {
                views.setTextViewText(R.id.widget_next, context.getString(R.string.widget_open_hint));
            }
        }

        Intent launchIntent = new Intent(Intent.ACTION_VIEW, Uri.parse("awwab://today"));
        launchIntent.setPackage(context.getPackageName());
        launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        PendingIntent pendingIntent = PendingIntent.getActivity(
            context, 0, launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
        );
        views.setOnClickPendingIntent(R.id.widget_root, pendingIntent);

        appWidgetManager.updateAppWidget(appWidgetId, views);
    }
}

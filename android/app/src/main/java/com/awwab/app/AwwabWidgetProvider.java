package com.awwab.app;

import android.app.PendingIntent;
import android.appwidget.AppWidgetManager;
import android.appwidget.AppWidgetProvider;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.net.Uri;
import android.view.View;
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
        int completed = prefs.getInt("completedCount", 0);
        int total = prefs.getInt("totalCount", 0);
        String next = prefs.getString("nextWorshipName", "");
        int pct = total > 0 ? Math.round(completed * 100f / total) : 0;
        boolean dayComplete = updatedAt > 0 && total > 0 && completed >= total;

        views.setViewVisibility(R.id.widget_completed_state, dayComplete ? View.VISIBLE : View.GONE);
        views.setViewVisibility(R.id.widget_progress_state, dayComplete ? View.GONE : View.VISIBLE);

        if (updatedAt == 0) {
            // لسه مفيش لقطة بيانات وصلت من التطبيق (أول تثبيت للودجت)
            views.setTextViewText(R.id.widget_percent, "—");
            views.setTextViewText(R.id.widget_summary, context.getString(R.string.widget_no_data));
            views.setTextViewText(R.id.widget_next, context.getString(R.string.widget_open_hint));
            views.setProgressBar(R.id.widget_progress_bar, 100, 0, false);
        } else if (dayComplete) {
            views.setTextViewText(R.id.widget_percent, "100%");
        } else {
            views.setTextViewText(R.id.widget_percent, pct + "%");
            views.setTextViewText(R.id.widget_summary, context.getString(R.string.widget_summary_format, completed, total));
            views.setProgressBar(R.id.widget_progress_bar, 100, pct, false);

            String nextLabel = next != null && !next.isEmpty() ? next : null;
            if (privacyMode && nextLabel != null) {
                // وضع الخصوصية: اسم العبادة نفسه مايتعرضش، بس نسبة
                // الإنجاز تفضل ظاهرة (مش حساسة بنفس درجة اسم العبادة)
                nextLabel = context.getString(R.string.widget_next_generic);
            }
            if (nextLabel != null) {
                views.setTextViewText(R.id.widget_next, context.getString(R.string.widget_next_format, nextLabel));
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

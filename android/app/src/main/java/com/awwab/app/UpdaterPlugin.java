package com.awwab.app;

import android.app.DownloadManager;
import android.content.Context;
import android.content.Intent;
import android.database.Cursor;
import android.net.Uri;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;

import androidx.core.content.FileProvider;

import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

import java.io.File;

// تنزيل تحديث أوّاب وفتح مثبّت أندرويد الرسمي عليه (Phase 7) — مفيش
// Silent Install هنا خالص، ده غير مسموح لأي تطبيق عادي على أندرويد؛
// المستخدم بيشوف تأكيد أندرويد الرسمي ويضغط "تثبيت" بنفسه. التحميل
// بيحصل جوه ملف التطبيق الخاص (External Files Dir)، ومفيش أي كلام
// عن مسح التطبيق القديم — التثبيت بيحصل فوق النسخة الحالية طالما
// نفس applicationId ونفس مفتاح التوقيع (راجع RELEASE.md).
@CapacitorPlugin(name = "Updater")
public class UpdaterPlugin extends Plugin {

    private static final String APK_FILE_NAME = "awwab-update.apk";
    private final Handler mainHandler = new Handler(Looper.getMainLooper());

    @PluginMethod
    public void canInstallUpdates(PluginCall call) {
        JSObject ret = new JSObject();
        ret.put("allowed", canRequestInstalls());
        call.resolve(ret);
    }

    @PluginMethod
    public void openInstallPermissionSettings(PluginCall call) {
        Context context = getContext();
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent intent = new Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:" + context.getPackageName()));
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            context.startActivity(intent);
        }
        call.resolve();
    }

    @PluginMethod
    public void downloadAndInstall(PluginCall call) {
        String apkUrl = call.getString("apkUrl");
        if (apkUrl == null || apkUrl.isEmpty()) {
            call.reject("apkUrl مطلوب");
            return;
        }
        if (!canRequestInstalls()) {
            JSObject ret = new JSObject();
            ret.put("needsPermission", true);
            call.resolve(ret);
            return;
        }

        Context context = getContext();
        File targetFile = new File(context.getExternalFilesDir(null), APK_FILE_NAME);
        if (targetFile.exists()) targetFile.delete();

        DownloadManager dm = (DownloadManager) context.getSystemService(Context.DOWNLOAD_SERVICE);
        DownloadManager.Request request = new DownloadManager.Request(Uri.parse(apkUrl));
        request.setTitle("تحديث أوّاب");
        request.setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED);
        request.setDestinationInExternalFilesDir(context, null, APK_FILE_NAME);
        request.setMimeType("application/vnd.android.package-archive");

        long downloadId = dm.enqueue(request);
        pollDownloadProgress(dm, downloadId, targetFile, call);
    }

    private void pollDownloadProgress(DownloadManager dm, long downloadId, File targetFile, PluginCall call) {
        mainHandler.postDelayed(() -> {
            DownloadManager.Query query = new DownloadManager.Query().setFilterById(downloadId);
            try (Cursor cursor = dm.query(query)) {
                if (cursor == null || !cursor.moveToFirst()) {
                    call.reject("تعذّر متابعة التحميل");
                    return;
                }
                int statusIdx = cursor.getColumnIndex(DownloadManager.COLUMN_STATUS);
                int bytesIdx = cursor.getColumnIndex(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR);
                int totalIdx = cursor.getColumnIndex(DownloadManager.COLUMN_TOTAL_SIZE_BYTES);
                int status = cursor.getInt(statusIdx);
                long bytes = cursor.getLong(bytesIdx);
                long total = cursor.getLong(totalIdx);

                if (status == DownloadManager.STATUS_SUCCESSFUL) {
                    JSObject progress = new JSObject();
                    progress.put("percent", 100);
                    notifyListeners("updateDownloadProgress", progress);
                    openInstaller(targetFile, call);
                    return;
                }
                if (status == DownloadManager.STATUS_FAILED) {
                    call.reject("فشل تحميل التحديث");
                    return;
                }
                if (total > 0) {
                    JSObject progress = new JSObject();
                    progress.put("percent", (int) (bytes * 100 / total));
                    notifyListeners("updateDownloadProgress", progress);
                }
                pollDownloadProgress(dm, downloadId, targetFile, call);
            }
        }, 400);
    }

    private void openInstaller(File apkFile, PluginCall call) {
        Context context = getContext();
        Uri contentUri = FileProvider.getUriForFile(context, context.getPackageName() + ".fileprovider", apkFile);
        Intent installIntent = new Intent(Intent.ACTION_VIEW);
        installIntent.setDataAndType(contentUri, "application/vnd.android.package-archive");
        installIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_GRANT_READ_URI_PERMISSION);
        context.startActivity(installIntent);
        JSObject ret = new JSObject();
        ret.put("installerOpened", true);
        call.resolve(ret);
    }

    private boolean canRequestInstalls() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return true; // مش لازم إذن قبل أندرويد 8
        return getContext().getPackageManager().canRequestPackageInstalls();
    }
}

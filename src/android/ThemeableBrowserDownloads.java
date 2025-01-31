package com.initialxy.cordova.themeablebrowser;

import android.content.Intent;
import android.net.Uri;
import android.os.Build;

import org.apache.cordova.CordovaWebView;
import org.json.JSONException;

//Download Files imports
import android.app.DownloadManager;
import android.os.Environment;
import android.webkit.DownloadListener;
import android.webkit.URLUtil;
import android.widget.Toast;

import static android.content.Context.DOWNLOAD_SERVICE;

//Permissions
import android.content.pm.PackageManager;

public class ThemeableBrowserDownloads implements DownloadListener{

    ThemeableBrowser plugin;

    String url;
    String userAgent;
    String contentDisposition;
    String mimetype;
    long contentLength;

    public ThemeableBrowserDownloads(ThemeableBrowser plugin) {
        this.plugin = plugin;
    }


    public void onDownloadStart(String url, String userAgent,
                                String contentDisposition, String mimetype,
                                long contentLength) {

        ThemeableBrowserDownloads.this.url = url;
        ThemeableBrowserDownloads.this.userAgent = userAgent;
        ThemeableBrowserDownloads.this.contentDisposition = contentDisposition;
        ThemeableBrowserDownloads.this.mimetype = mimetype;
        ThemeableBrowserDownloads.this.contentLength = contentLength;


        if (Build.VERSION.SDK_INT >= 23) {
            if (plugin.cordova.getActivity().checkSelfPermission(android.Manifest.permission.WRITE_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED) {
                processDownload();
            } else {
                plugin.cordova.requestPermission(ThemeableBrowserDownloads.this.plugin, 0, android.Manifest.permission.WRITE_EXTERNAL_STORAGE);
            }
        } else { //permission is automatically granted on sdk<23 upon installation
            processDownload();
        }
    }

    public void onRequestPermissionResult(int requestCode, String[] permissions,
                                          int[] grantResults) throws JSONException
    {
        for(int r:grantResults)
        {
            if(r == PackageManager.PERMISSION_DENIED)
            {
                Toast.makeText(plugin.cordova.getActivity().getApplicationContext(), "Error downloading file, missing storage permissions", Toast.LENGTH_LONG).show();
            } else {
                ThemeableBrowserDownloads.this.processDownload();
            }
        }
    }

    protected void processDownload() {
        DownloadManager.Request request = new DownloadManager.Request(Uri.parse(ThemeableBrowserDownloads.this.url));
        try {
            request.allowScanningByMediaScanner();
            request.setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED); //Notify client once download is completed!
            final String filename = URLUtil.guessFileName(ThemeableBrowserDownloads.this.url, ThemeableBrowserDownloads.this.contentDisposition, ThemeableBrowserDownloads.this.mimetype);
            request.setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, filename);
            DownloadManager dm = (DownloadManager) plugin.cordova.getActivity().getSystemService(DOWNLOAD_SERVICE);
            dm.enqueue(request);
            Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT); //This is important!
            intent.addCategory(Intent.CATEGORY_OPENABLE); //CATEGORY.OPENABLE
            intent.setType("*/*");//any application,any extension
            Toast.makeText(plugin.cordova.getActivity().getApplicationContext(), "Downloading File '" + filename + "'", Toast.LENGTH_LONG).show();
        } catch (Exception exception) {
            Toast.makeText(plugin.cordova.getActivity().getApplicationContext(), "Error downloading file, missing storage permissions", Toast.LENGTH_LONG).show();
            exception.printStackTrace();
        }
    }
}
package com.awwab.app;

import android.os.Bundle;
import com.getcapacitor.BridgeActivity;

public class MainActivity extends BridgeActivity {
    @Override
    public void onCreate(Bundle savedInstanceState) {
        // Plugins محلية (مش من npm) — لازم تتسجّل يدويًا قبل super.onCreate()
        registerPlugin(WidgetBridgePlugin.class);
        registerPlugin(WidgetPinPlugin.class);
        registerPlugin(UpdaterPlugin.class);
        super.onCreate(savedInstanceState);
    }
}

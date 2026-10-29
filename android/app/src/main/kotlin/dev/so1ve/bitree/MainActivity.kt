package dev.so1ve.bitree

import android.content.res.Configuration
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        TimetableWidget.updateAll(this)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.so1ve.bitree/widget")
            .setMethodCallHandler { call, result ->
                if (call.method == "update") {
                    call.argument<Map<String, List<Number>>>("darkCourseColors")?.let {
                        BuildingColors.saveDarkPalette(this, it)
                    }
                    call.argument<Boolean>("useSystemPalette")?.let {
                        WidgetColors.saveUseSystemPalette(this, it)
                    }
                    TimetableWidget.updateAll(this)
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }
}

package com.margelo.nitro.PharmaScanner

import android.view.View
import com.facebook.react.ReactPackage
import com.facebook.react.bridge.NativeModule
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.uimanager.ViewManager

class PharmaScannerViewPackage : ReactPackage {

    @Suppress("DEPRECATION")
    override fun createNativeModules(reactContext: ReactApplicationContext): List<NativeModule> {
        return emptyList()
    }

    override fun createViewManagers(reactContext: ReactApplicationContext): List<ViewManager<out View, *>> {
        return listOf(PharmaScannerCameraViewManager())
    }
}

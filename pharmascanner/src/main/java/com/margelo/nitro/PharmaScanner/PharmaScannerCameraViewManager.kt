package com.margelo.nitro.PharmaScanner

import com.facebook.react.uimanager.SimpleViewManager
import com.facebook.react.uimanager.ThemedReactContext

class PharmaScannerCameraViewManager : SimpleViewManager<PharmaScannerCameraView>() {

    override fun getName(): String = "PharmaScannerCameraView"

    override fun createViewInstance(reactContext: ThemedReactContext): PharmaScannerCameraView {
        return PharmaScannerCameraView(reactContext)
    }
}

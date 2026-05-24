package com.margelo.nitro.PharmaScanner

import android.graphics.Color
import com.facebook.react.uimanager.SimpleViewManager
import com.facebook.react.uimanager.ThemedReactContext
import com.facebook.react.uimanager.annotations.ReactProp

class PharmaScannerCameraViewManager : SimpleViewManager<PharmaScannerCameraView>() {

    override fun getName(): String = "PharmaScannerCameraView"

    override fun createViewInstance(reactContext: ThemedReactContext): PharmaScannerCameraView {
        return PharmaScannerCameraView(reactContext)
    }

    @ReactProp(name = "overlayColor")
    fun setOverlayColor(view: PharmaScannerCameraView, color: String?) {
        val parsed = parseHexColor(color) ?: return
        view.setOverlayStrokeColor(parsed)
    }

    @ReactProp(name = "overlayLineWidth", defaultFloat = 3f)
    fun setOverlayLineWidth(view: PharmaScannerCameraView, width: Float) {
        view.setOverlayLineWidthValue(width)
    }

    @ReactProp(name = "overlayFillColor")
    fun setOverlayFillColor(view: PharmaScannerCameraView, color: String?) {
        val parsed = parseHexColor(color) ?: return
        view.setOverlayFillColorValue(parsed)
    }

    @ReactProp(name = "showOverlay", defaultBoolean = true)
    fun setShowOverlay(view: PharmaScannerCameraView, show: Boolean) {
        view.setShowOverlayValue(show)
    }

    companion object {
        /**
         * Parses hex color strings in #RRGGBB or #RRGGBBAA format.
         * Android's Color.parseColor expects #AARRGGBB for 8-digit hex,
         * so we convert #RRGGBBAA → #AARRGGBB before parsing.
         */
        private fun parseHexColor(hex: String?): Int? {
            if (hex == null) return null
            return try {
                if (hex.length == 9 && hex.startsWith("#")) {
                    // #RRGGBBAA → #AARRGGBB
                    val converted = "#" + hex.substring(7, 9) + hex.substring(1, 7)
                    Color.parseColor(converted)
                } else {
                    Color.parseColor(hex)
                }
            } catch (_: IllegalArgumentException) {
                null
            }
        }
    }
}

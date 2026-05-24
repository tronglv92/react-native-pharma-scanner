package com.margelo.nitro.PharmaScanner

import android.content.Context
import android.graphics.Color
import android.widget.FrameLayout
import androidx.camera.view.PreviewView

class PharmaScannerCameraView(context: Context) : FrameLayout(context) {

    private val barcodeOverlay: BarcodeOverlayView

    init {
        setBackgroundColor(Color.BLACK)

        val previewView = PreviewView(context).apply {
            implementationMode = PreviewView.ImplementationMode.PERFORMANCE
            scaleType = PreviewView.ScaleType.FILL_CENTER
        }
        addView(previewView, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        CameraManager.bindPreview(previewView)

        barcodeOverlay = BarcodeOverlayView(context)
        addView(barcodeOverlay, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))

        CameraManager.bindOverlay(this)
    }

    private val measureAndLayout = Runnable {
        measure(
            MeasureSpec.makeMeasureSpec(width, MeasureSpec.EXACTLY),
            MeasureSpec.makeMeasureSpec(height, MeasureSpec.EXACTLY)
        )
        layout(left, top, right, bottom)
    }

    override fun requestLayout() {
        super.requestLayout()
        removeCallbacks(measureAndLayout)
        post(measureAndLayout)
    }

    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        val w = right - left
        val h = bottom - top
        for (i in 0 until childCount) {
            val child = getChildAt(i)
            child.measure(
                MeasureSpec.makeMeasureSpec(w, MeasureSpec.EXACTLY),
                MeasureSpec.makeMeasureSpec(h, MeasureSpec.EXACTLY)
            )
            child.layout(0, 0, w, h)
        }
    }

    // MARK: - Barcode overlay updates from CameraManager

    fun updateBarcodeDetections(rects: List<FrameRect>) {
        barcodeOverlay.updateBarcodes(rects)
    }

    fun clearAllOverlays() {
        barcodeOverlay.clear()
    }

    // MARK: - Prop setters forwarded to BarcodeOverlayView

    fun setOverlayStrokeColor(color: Int) {
        barcodeOverlay.setStrokeColor(color)
    }

    fun setOverlayFillColorValue(color: Int) {
        barcodeOverlay.setFillColor(color)
    }

    fun setOverlayLineWidthValue(widthDp: Float) {
        barcodeOverlay.setLineWidth(widthDp)
    }

    fun setShowOverlayValue(show: Boolean) {
        barcodeOverlay.setShowOverlay(show)
    }
}

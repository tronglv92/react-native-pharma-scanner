package com.margelo.nitro.PharmaScanner

import android.content.Context
import android.graphics.Color
import android.widget.FrameLayout
import androidx.camera.view.PreviewView

class PharmaScannerCameraView(context: Context) : FrameLayout(context) {

    private val overlayView: DocumentOverlayView

    init {
        setBackgroundColor(Color.BLACK)

        val previewView = PreviewView(context).apply {
            implementationMode = PreviewView.ImplementationMode.COMPATIBLE
            scaleType = PreviewView.ScaleType.FILL_CENTER
        }
        addView(previewView, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        CameraManager.bindPreview(previewView)

        overlayView = DocumentOverlayView(context)
        addView(overlayView, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        CameraManager.bindOverlay(overlayView)
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
}

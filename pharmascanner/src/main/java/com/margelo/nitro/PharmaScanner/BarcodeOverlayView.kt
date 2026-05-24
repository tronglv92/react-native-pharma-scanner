package com.margelo.nitro.PharmaScanner

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.view.View

class BarcodeOverlayView(context: Context) : View(context) {

    private var barcodeRects: List<FrameRect> = emptyList()
    private var showOverlay: Boolean = true

    private val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        color = Color.parseColor("#4CAF50")
        strokeWidth = 3f * resources.displayMetrics.density
        strokeJoin = Paint.Join.ROUND
        strokeCap = Paint.Cap.ROUND
    }

    private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
        color = 0x264CAF50 // green with ~15% alpha
    }

    fun setStrokeColor(color: Int) {
        strokePaint.color = color
        invalidate()
    }

    fun setFillColor(color: Int) {
        fillPaint.color = color
        invalidate()
    }

    fun setLineWidth(widthDp: Float) {
        strokePaint.strokeWidth = widthDp * resources.displayMetrics.density
        invalidate()
    }

    fun setShowOverlay(show: Boolean) {
        showOverlay = show
        invalidate()
    }

    fun updateBarcodes(rects: List<FrameRect>) {
        barcodeRects = rects
        invalidate()
    }

    fun clear() {
        barcodeRects = emptyList()
        invalidate()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)

        if (!showOverlay || barcodeRects.isEmpty()) return

        val w = width.toFloat()
        val h = height.toFloat()
        val cornerRadius = 4f * resources.displayMetrics.density

        for (rect in barcodeRects) {
            val left = (rect.x * w).toFloat()
            val top = (rect.y * h).toFloat()
            val right = ((rect.x + rect.width) * w).toFloat()
            val bottom = ((rect.y + rect.height) * h).toFloat()

            val rectF = RectF(left, top, right, bottom)
            canvas.drawRoundRect(rectF, cornerRadius, cornerRadius, fillPaint)
            canvas.drawRoundRect(rectF, cornerRadius, cornerRadius, strokePaint)
        }
    }
}

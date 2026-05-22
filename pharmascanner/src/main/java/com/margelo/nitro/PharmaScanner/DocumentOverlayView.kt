package com.margelo.nitro.PharmaScanner

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.CornerPathEffect
import android.graphics.Paint
import android.graphics.Path
import android.util.Log
import android.view.View

class DocumentOverlayView(context: Context) : View(context) {
    companion object {
        private const val TAG = "DocumentOverlayView"
        private const val LERP_FACTOR = 0.35f
    }

    private var targetCorners: FloatArray? = null
    private var currentCorners: FloatArray? = null
    private var imageWidth = 0
    private var imageHeight = 0
    private var confidence = 0.0
    private var isStable = false

    private val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#4CAF50")
        style = Paint.Style.STROKE
        strokeWidth = 6f
        strokeJoin = Paint.Join.ROUND
        strokeCap = Paint.Cap.ROUND
        pathEffect = CornerPathEffect(16f)
    }

    private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#264CAF50")
        style = Paint.Style.FILL
    }

    private val textBgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#CC000000")
        style = Paint.Style.FILL
    }

    private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        textSize = 36f
        isFakeBoldText = true
    }

    private val stableTextPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#4CAF50")
        textSize = 36f
        isFakeBoldText = true
    }

    private val path = Path()

    fun updateDetection(detection: DocumentDetection?, imgW: Int, imgH: Int) {
        imageWidth = imgW
        imageHeight = imgH

        if (detection != null && detection.detected) {
            confidence = detection.confidence
            isStable = detection.isStable
            val viewCoords = mapToViewCoords(detection.corners)
            targetCorners = viewCoords
            if (currentCorners == null) {
                currentCorners = viewCoords.copyOf()
            }
        } else {
            targetCorners = null
            currentCorners = null
            confidence = 0.0
            isStable = false
        }
        postInvalidate()
    }

    private fun mapToViewCoords(c: Corners): FloatArray {
        val vw = width.toFloat()
        val vh = height.toFloat()

        if (vw <= 0 || vh <= 0 || imageWidth <= 0 || imageHeight <= 0) {
            return floatArrayOf(
                (c.topLeft.x * vw).toFloat(), (c.topLeft.y * vh).toFloat(),
                (c.topRight.x * vw).toFloat(), (c.topRight.y * vh).toFloat(),
                (c.bottomRight.x * vw).toFloat(), (c.bottomRight.y * vh).toFloat(),
                (c.bottomLeft.x * vw).toFloat(), (c.bottomLeft.y * vh).toFloat()
            )
        }

        val camAspect = imageWidth.toFloat() / imageHeight.toFloat()
        val viewAspect = vw / vh

        val offsetX: Float
        val offsetY: Float
        val scaleX: Float
        val scaleY: Float

        if (camAspect > viewAspect) {
            val scale = vh / imageHeight.toFloat()
            val displayW = imageWidth * scale
            offsetX = (displayW - vw) / 2f
            offsetY = 0f
            scaleX = displayW
            scaleY = vh
        } else {
            val scale = vw / imageWidth.toFloat()
            val displayH = imageHeight * scale
            offsetX = 0f
            offsetY = (displayH - vh) / 2f
            scaleX = vw
            scaleY = displayH
        }

        return floatArrayOf(
            (c.topLeft.x * scaleX - offsetX).toFloat(), (c.topLeft.y * scaleY - offsetY).toFloat(),
            (c.topRight.x * scaleX - offsetX).toFloat(), (c.topRight.y * scaleY - offsetY).toFloat(),
            (c.bottomRight.x * scaleX - offsetX).toFloat(), (c.bottomRight.y * scaleY - offsetY).toFloat(),
            (c.bottomLeft.x * scaleX - offsetX).toFloat(), (c.bottomLeft.y * scaleY - offsetY).toFloat()
        )
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)

        val target = targetCorners
        val current = currentCorners

        if (target != null && current != null) {
            // Interpolate for smooth animation
            var needsRedraw = false
            for (i in current.indices) {
                val diff = target[i] - current[i]
                if (absF(diff) > 0.5f) {
                    current[i] += diff * LERP_FACTOR
                    needsRedraw = true
                } else {
                    current[i] = target[i]
                }
            }

            // Draw the green border
            path.reset()
            path.moveTo(current[0], current[1])
            path.lineTo(current[2], current[3])
            path.lineTo(current[4], current[5])
            path.lineTo(current[6], current[7])
            path.close()

            canvas.drawPath(path, fillPaint)
            canvas.drawPath(path, strokePaint)

            if (needsRedraw) {
                postInvalidateOnAnimation()
            }
        }

        // Always draw confidence info at the top
        drawInfoBadge(canvas)
    }

    private fun drawInfoBadge(canvas: Canvas) {
        val confPercent = (confidence * 100).toInt()
        val text = if (targetCorners != null) {
            if (isStable) "Stable | $confPercent%" else "Detected | $confPercent%"
        } else {
            "Scanning..."
        }

        val paint = if (isStable && targetCorners != null) stableTextPaint else textPaint
        val textWidth = paint.measureText(text)
        val padding = 16f
        val badgeHeight = 48f
        val x = (width - textWidth) / 2f - padding
        val y = 24f

        // Background pill
        canvas.drawRoundRect(
            x, y, x + textWidth + padding * 2, y + badgeHeight,
            24f, 24f, textBgPaint
        )
        // Text
        canvas.drawText(text, x + padding, y + 34f, paint)
    }

    private fun absF(v: Float): Float = if (v < 0) -v else v
}

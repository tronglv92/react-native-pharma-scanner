package com.margelo.nitro.PharmaScanner

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Paint
import android.net.Uri
import android.util.Log
import java.io.File
import java.io.FileOutputStream
import java.util.UUID
import kotlin.math.max
import kotlin.math.roundToInt
import kotlin.math.sqrt

object ImageProcessor {
    private const val TAG = "ImageProcessor"

    fun cropAndCorrect(imageUri: String, corners: Corners): Triple<String, Int, Int> {
        val context = ActivityProvider.applicationContext

        val uri = Uri.parse(imageUri)
        val srcBitmap = if (uri.scheme == "file") {
            BitmapFactory.decodeFile(uri.path)
        } else {
            context.contentResolver.openInputStream(uri)?.use { stream ->
                BitmapFactory.decodeStream(stream)
            }
        } ?: throw IllegalArgumentException("Could not load image from URI: $imageUri")

        val imgW = srcBitmap.width.toFloat()
        val imgH = srcBitmap.height.toFloat()

        // Convert normalized corners (0-1) to pixel coordinates
        val tlX = (corners.topLeft.x * imgW).toFloat()
        val tlY = (corners.topLeft.y * imgH).toFloat()
        val trX = (corners.topRight.x * imgW).toFloat()
        val trY = (corners.topRight.y * imgH).toFloat()
        val blX = (corners.bottomLeft.x * imgW).toFloat()
        val blY = (corners.bottomLeft.y * imgH).toFloat()
        val brX = (corners.bottomRight.x * imgW).toFloat()
        val brY = (corners.bottomRight.y * imgH).toFloat()

        // Calculate output dimensions from corner distances
        val topWidth = distance(tlX, tlY, trX, trY)
        val bottomWidth = distance(blX, blY, brX, brY)
        val leftHeight = distance(tlX, tlY, blX, blY)
        val rightHeight = distance(trX, trY, brX, brY)

        val outW = max(topWidth, bottomWidth).roundToInt().coerceAtLeast(1)
        val outH = max(leftHeight, rightHeight).roundToInt().coerceAtLeast(1)

        // Source points: topLeft, topRight, bottomRight, bottomLeft
        val srcPts = floatArrayOf(
            tlX, tlY,
            trX, trY,
            brX, brY,
            blX, blY
        )

        // Destination points: rectangle corners
        val dstPts = floatArrayOf(
            0f, 0f,
            outW.toFloat(), 0f,
            outW.toFloat(), outH.toFloat(),
            0f, outH.toFloat()
        )

        val matrix = Matrix()
        matrix.setPolyToPoly(srcPts, 0, dstPts, 0, 4)

        val outputBitmap = Bitmap.createBitmap(outW, outH, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(outputBitmap)
        val paint = Paint().apply {
            isAntiAlias = true
            isFilterBitmap = true
        }
        canvas.drawBitmap(srcBitmap, matrix, paint)
        srcBitmap.recycle()

        // Save as JPEG to cache dir
        val fileName = "${UUID.randomUUID()}.jpg"
        val outputFile = File(context.cacheDir, fileName)
        FileOutputStream(outputFile).use { out ->
            outputBitmap.compress(Bitmap.CompressFormat.JPEG, 90, out)
        }

        val resultWidth = outputBitmap.width
        val resultHeight = outputBitmap.height
        outputBitmap.recycle()

        val outputUri = "file://${outputFile.absolutePath}"
        Log.d(TAG, "Corrected image saved: $outputUri (${resultWidth}x${resultHeight})")

        return Triple(outputUri, resultWidth, resultHeight)
    }

    /**
     * Enhance a scanned document image to fix blur and dark spots.
     * 1. Gamma correction (gamma < 1) brightens dark areas non-linearly,
     *    lifting shadows/dark spots without over-exposing bright areas.
     * 2. 3x3 Laplacian sharpening kernel restores edge clarity lost to
     *    auto-capture motion or slight defocus.
     */
    fun enhanceScannedImage(imageUri: String): Triple<String, Int, Int> {
        val context = ActivityProvider.applicationContext
        val uri = Uri.parse(imageUri)

        val srcBitmap = if (uri.scheme == "file") {
            BitmapFactory.decodeFile(uri.path)
        } else {
            context.contentResolver.openInputStream(uri)?.use { stream ->
                BitmapFactory.decodeStream(stream)
            }
        } ?: throw IllegalArgumentException("Could not load image: $imageUri")

        val width = srcBitmap.width
        val height = srcBitmap.height
        val pixels = IntArray(width * height)
        srcBitmap.getPixels(pixels, 0, width, 0, 0, width, height)
        srcBitmap.recycle()

        Log.d(TAG, "Enhancing scanned image: ${width}x${height}")

        // Step 1: Gamma correction to brighten dark spots (gamma < 1 = brighten)
        val gamma = 0.85
        val gammaLut = IntArray(256) { i ->
            (255.0 * Math.pow(i / 255.0, gamma)).roundToInt().coerceIn(0, 255)
        }
        for (i in pixels.indices) {
            val p = pixels[i]
            val a = (p shr 24) and 0xFF
            val r = gammaLut[(p shr 16) and 0xFF]
            val g = gammaLut[(p shr 8) and 0xFF]
            val b = gammaLut[p and 0xFF]
            pixels[i] = (a shl 24) or (r shl 16) or (g shl 8) or b
        }

        // Step 2: Sharpen using 3x3 Laplacian kernel [0,-1,0; -1,5,-1; 0,-1,0]
        val sharpened = IntArray(pixels.size)
        System.arraycopy(pixels, 0, sharpened, 0, pixels.size)

        for (y in 1 until height - 1) {
            for (x in 1 until width - 1) {
                val idx = y * width + x
                val c = pixels[idx]
                val t = pixels[idx - width]
                val bt = pixels[idx + width]
                val l = pixels[idx - 1]
                val ri = pixels[idx + 1]

                val red = (5 * ((c shr 16) and 0xFF)
                        - ((t shr 16) and 0xFF) - ((bt shr 16) and 0xFF)
                        - ((l shr 16) and 0xFF) - ((ri shr 16) and 0xFF)).coerceIn(0, 255)
                val green = (5 * ((c shr 8) and 0xFF)
                        - ((t shr 8) and 0xFF) - ((bt shr 8) and 0xFF)
                        - ((l shr 8) and 0xFF) - ((ri shr 8) and 0xFF)).coerceIn(0, 255)
                val blue = (5 * (c and 0xFF)
                        - (t and 0xFF) - (bt and 0xFF)
                        - (l and 0xFF) - (ri and 0xFF)).coerceIn(0, 255)
                val alpha = (c shr 24) and 0xFF

                sharpened[idx] = (alpha shl 24) or (red shl 16) or (green shl 8) or blue
            }
        }

        val outputBitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        outputBitmap.setPixels(sharpened, 0, width, 0, 0, width, height)

        val fileName = "${UUID.randomUUID()}.jpg"
        val outputFile = File(context.cacheDir, fileName)
        FileOutputStream(outputFile).use { out ->
            outputBitmap.compress(Bitmap.CompressFormat.JPEG, 95, out)
        }

        val resultWidth = outputBitmap.width
        val resultHeight = outputBitmap.height
        outputBitmap.recycle()

        val outputUri = "file://${outputFile.absolutePath}"
        Log.d(TAG, "Enhanced image saved: $outputUri (${resultWidth}x${resultHeight})")

        return Triple(outputUri, resultWidth, resultHeight)
    }

    private fun distance(x1: Float, y1: Float, x2: Float, y2: Float): Float {
        val dx = x2 - x1
        val dy = y2 - y1
        return sqrt(dx * dx + dy * dy)
    }
}

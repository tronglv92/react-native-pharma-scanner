package com.margelo.nitro.PharmaScanner

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import org.opencv.android.Utils
import org.opencv.core.CvType
import org.opencv.core.Mat
import org.opencv.core.MatOfPoint2f
import org.opencv.core.Size
import org.opencv.imgproc.Imgproc
import java.io.File
import java.io.FileOutputStream
import java.util.UUID
import kotlin.math.sqrt

object ImageProcessor {

    fun cropAndCorrect(context: Context, imageUri: String, corners: Corners): Triple<String, Int, Int> {
        val path = if (imageUri.startsWith("file://")) {
            imageUri.removePrefix("file://")
        } else {
            imageUri
        }

        val bitmap = BitmapFactory.decodeFile(path)
            ?: throw IllegalStateException("Failed to load image from URI: $imageUri")

        val srcMat = Mat()
        Utils.bitmapToMat(bitmap, srcMat)
        val imageWidth = bitmap.width.toDouble()
        val imageHeight = bitmap.height.toDouble()
        bitmap.recycle()

        // Convert normalized corners to pixel coordinates
        val tl = org.opencv.core.Point(corners.topLeft.x * imageWidth, corners.topLeft.y * imageHeight)
        val tr = org.opencv.core.Point(corners.topRight.x * imageWidth, corners.topRight.y * imageHeight)
        val bl = org.opencv.core.Point(corners.bottomLeft.x * imageWidth, corners.bottomLeft.y * imageHeight)
        val br = org.opencv.core.Point(corners.bottomRight.x * imageWidth, corners.bottomRight.y * imageHeight)

        // Calculate output dimensions
        val widthTop = distance(tl, tr)
        val widthBottom = distance(bl, br)
        val outputWidth = maxOf(widthTop, widthBottom).toInt()

        val heightLeft = distance(tl, bl)
        val heightRight = distance(tr, br)
        val outputHeight = maxOf(heightLeft, heightRight).toInt()

        val srcPoints = MatOfPoint2f(tl, tr, br, bl)
        val dstPoints = MatOfPoint2f(
            org.opencv.core.Point(0.0, 0.0),
            org.opencv.core.Point(outputWidth.toDouble(), 0.0),
            org.opencv.core.Point(outputWidth.toDouble(), outputHeight.toDouble()),
            org.opencv.core.Point(0.0, outputHeight.toDouble())
        )

        val transform = Imgproc.getPerspectiveTransform(srcPoints, dstPoints)
        val dstMat = Mat()
        Imgproc.warpPerspective(srcMat, dstMat, transform, Size(outputWidth.toDouble(), outputHeight.toDouble()))

        srcMat.release()
        srcPoints.release()
        dstPoints.release()
        transform.release()

        // Convert back to bitmap and save
        val resultBitmap = Bitmap.createBitmap(outputWidth, outputHeight, Bitmap.Config.ARGB_8888)
        Utils.matToBitmap(dstMat, resultBitmap)
        dstMat.release()

        val fileName = "${UUID.randomUUID()}.jpg"
        val file = File(context.cacheDir, fileName)
        FileOutputStream(file).use { out ->
            resultBitmap.compress(Bitmap.CompressFormat.JPEG, 90, out)
        }
        resultBitmap.recycle()

        return Triple("file://${file.absolutePath}", outputWidth, outputHeight)
    }

    private fun distance(p1: org.opencv.core.Point, p2: org.opencv.core.Point): Double {
        val dx = p1.x - p2.x
        val dy = p1.y - p2.y
        return sqrt(dx * dx + dy * dy)
    }
}

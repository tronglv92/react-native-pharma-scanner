package com.margelo.nitro.PharmaScanner

import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.lifecycle.LifecycleOwner
import com.margelo.nitro.core.Promise

class HybridPharmaScanner : HybridPharmaScannerSpec() {

    companion object {
        private const val TAG = "HybridPharmaScanner"
        private val mainHandler = Handler(Looper.getMainLooper())
    }

    override fun ping(): String = "pong"
    override fun getVersion(): String = "0.0.1"

    override fun startCamera(): Unit {
        mainHandler.post {
            val activity = ActivityProvider.currentActivity ?: run {
                Log.w(TAG, "startCamera: no current activity")
                return@post
            }

            val componentActivity = activity as? ComponentActivity ?: run {
                Log.w(TAG, "startCamera: activity is not a ComponentActivity")
                return@post
            }

            val lifecycleOwner = activity as? LifecycleOwner ?: run {
                Log.w(TAG, "startCamera: activity is not a LifecycleOwner")
                return@post
            }

            PermissionHelper.requestCameraPermission(componentActivity) { granted ->
                if (granted) {
                    CameraManager.startSession(activity, lifecycleOwner)
                } else {
                    Log.w(TAG, "Camera permission denied")
                }
            }
        }
    }

    override fun stopCamera(): Unit {
        CameraManager.stopSession()
    }

    override fun capturePhoto(): Promise<CapturedImage> {
        return Promise.async {
            val activity = ActivityProvider.currentActivity
                ?: throw IllegalStateException("Activity not available")

            val (uri, width, height) = CameraManager.capturePhoto(activity)

            CapturedImage(
                uri = uri,
                width = width.toDouble(),
                height = height.toDouble(),
                base64 = null
            )
        }
    }

    override fun setFlash(mode: FlashMode): Unit {
        CameraManager.setFlashMode(mode)
    }

    override fun setZoom(factor: Double): Unit {
        CameraManager.setZoom(factor)
    }

    override fun detectDocument(imageUri: String): Promise<DocumentDetection> {
        return Promise.async {
            val detector = DocumentDetector()
            detector.detectDocument(imageUri)
        }
    }

    override fun cropAndCorrect(imageUri: String, corners: Corners): Promise<CapturedImage> {
        return Promise.async {
            val activity = ActivityProvider.currentActivity
                ?: throw IllegalStateException("Activity not available")

            val (uri, width, height) = ImageProcessor.cropAndCorrect(activity, imageUri, corners)

            CapturedImage(
                uri = uri,
                width = width.toDouble(),
                height = height.toDouble(),
                base64 = null
            )
        }
    }

    override fun setOnDocumentDetected(callback: (detection: DocumentDetection) -> Unit): Unit {
        CameraManager.setOnDocumentDetected(callback)
    }
}

package com.margelo.nitro.PharmaScanner

import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.lifecycle.LifecycleOwner
import com.margelo.nitro.core.Promise
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

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
            throw UnsupportedOperationException("Use scanDocument() on Android")
        }
    }

    override fun cropAndCorrect(imageUri: String, corners: Corners): Promise<CapturedImage> {
        return Promise.async {
            throw UnsupportedOperationException("Use scanDocument() on Android")
        }
    }

    override fun setOnDocumentDetected(callback: (detection: DocumentDetection) -> Unit): Unit {
        Log.d(TAG, "setOnDocumentDetected is a no-op on Android. Use scanDocument() instead.")
    }

    override fun scanDocument(): Promise<Array<CapturedImage>> {
        return Promise.async {
            val result = DocumentScannerManager.scanDocument()
            result.toTypedArray()
        }
    }

    override fun scanBarcodes(options: BarcodeScanOptions): Promise<Array<BarcodeResult>> {
        return Promise.async {
            BarcodeScannerManager.scanBarcodes(options)
        }
    }

    override fun startContinuousScan(formats: Array<BarcodeFormat>, onDetected: (codes: Array<BarcodeResult>) -> Unit): Unit {
        BarcodeScannerManager.onBarcodesDetectedCallback = onDetected
        BarcodeScannerManager.activeFormats = formats
        CameraManager.startContinuousScan(formats)
    }

    override fun stopContinuousScan(): Unit {
        CameraManager.stopContinuousScan()
    }

    override fun recognizeText(imageUri: String): Promise<OcrResult> {
        return Promise.async {
            OcrManager.recognizeText(imageUri)
        }
    }

    override fun setOnTextRecognized(callback: (result: OcrResult) -> Unit): Unit {
        OcrManager.onTextRecognizedCallback = callback
        Log.d(TAG, "setOnTextRecognized: registered callback. Use recognizeText() with image URI on Android.")
    }

    override fun recognizeDocument(imageUri: String): Promise<OcrResult> {
        return Promise.async {
            OcrManager.recognizeText(imageUri)
        }
    }

    override fun configure(apiKey: String, baseUrl: String): Unit {
        DocumentExtractor.configure(apiKey, baseUrl)
    }

    override fun extractDocument(imageUri: String, options: ExtractionOptions): Promise<DocumentExtractionResult> {
        Log.d(TAG, "extractDocument called: mode=${options.customPrompt}, type=${options.documentType}")
        return Promise.async {
            // Run entire extraction off the main thread to prevent ANR
            withContext(Dispatchers.Default) {
                Log.d(TAG, "extractDocument coroutine started on ${Thread.currentThread().name}")
                DocumentExtractor.extract(
                    imageUri = imageUri,
                    documentType = options.documentType,
                    language = options.language,
                    customPrompt = options.customPrompt,
                    forceOffline = options.forceOffline ?: false
                )
            }
        }
    }

    override fun isLocalLlmModelReady(): Boolean {
        return try {
            LlamaCppManager.isModelDownloaded
        } catch (e: Exception) {
            Log.w(TAG, "isLocalLlmModelReady check failed", e)
            false
        }
    }

    override fun downloadLocalLlmModel(onProgress: (progress: Double) -> Unit): Promise<Unit> {
        return Promise.async {
            LlamaCppManager.downloadModel { progress ->
                onProgress(progress)
            }
        }
    }

    override fun unloadLocalLlmModel(): Unit {
        LlamaCppManager.unloadModel()
    }
}

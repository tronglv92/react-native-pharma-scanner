package com.margelo.nitro.PharmaScanner

import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL

object LlamaCppManager {
    private const val TAG = "LlamaCppManager"

    private const val MODEL_FILE_NAME = "Qwen3-0.6B-Q4_K_M.gguf"
    private const val MODEL_DOWNLOAD_URL =
        "https://huggingface.co/unsloth/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q4_K_M.gguf"

    // N_GPU_LAYERS: 0 for Android (CPU-only, no Metal)
    private const val N_GPU_LAYERS = 0

    private var nativeLibLoaded = false

    private fun ensureNativeLib() {
        if (!nativeLibLoaded) {
            // Load shared library dependencies in order (BUILD_SHARED_LIBS=ON)
            System.loadLibrary("ggml-base")
            System.loadLibrary("ggml")
            System.loadLibrary("llama")
            System.loadLibrary("llama_bridge")
            // Initialize backend with path to native .so files so the best
            // CPU variant (DOTPROD, SVE2, etc.) is auto-selected at runtime
            val context = ActivityProvider.applicationContext
            val nativeLibDir = context.applicationInfo.nativeLibraryDir
            Log.i(TAG, "Native lib dir: $nativeLibDir")
            nativeInitBackend(nativeLibDir)
            nativeLibLoaded = true
        }
    }

    // JNI native methods
    private external fun nativeInitBackend(nativeLibDir: String)
    private external fun nativeLoadModel(modelPath: String, nGpuLayers: Int): Boolean
    private external fun nativeGenerate(prompt: String, maxTokens: Int): String
    private external fun nativeUnloadModel()
    private external fun nativeIsLoaded(): Boolean

    // --- Model file paths ---

    private fun modelsDir(): File {
        val context = ActivityProvider.applicationContext
        val dir = File(context.filesDir, "models")
        if (!dir.exists()) dir.mkdirs()
        return dir
    }

    private fun modelFile(): File = File(modelsDir(), MODEL_FILE_NAME)

    // --- Public API ---

    val isModelDownloaded: Boolean
        get() = modelFile().exists()

    val isModelLoaded: Boolean
        get() {
            ensureNativeLib()
            return nativeIsLoaded()
        }

    fun loadModel() {
        ensureNativeLib()
        if (isModelLoaded) return
        if (!isModelDownloaded) {
            throw IllegalStateException("Model file not found. Please download the model first.")
        }
        val success = nativeLoadModel(modelFile().absolutePath, N_GPU_LAYERS)
        if (!success) {
            throw RuntimeException("Failed to load the GGUF model file.")
        }
        Log.i(TAG, "Model loaded successfully")
    }

    suspend fun generate(prompt: String): String = withContext(Dispatchers.Default) {
        ensureNativeLib()
        if (!nativeIsLoaded()) {
            throw IllegalStateException("Model is not loaded. Call loadModel() first.")
        }
        val result = nativeGenerate(prompt, 1024)
        result
    }

    fun unloadModel() {
        ensureNativeLib()
        nativeUnloadModel()
        Log.i(TAG, "Model unloaded")
    }

    suspend fun downloadModel(onProgress: (Double) -> Unit) = withContext(Dispatchers.IO) {
        if (isModelDownloaded) {
            onProgress(1.0)
            return@withContext
        }

        // Check if model was side-loaded to the Download folder
        val sideLoaded = findSideLoadedModel()
        if (sideLoaded != null) {
            Log.i(TAG, "Found side-loaded model at: ${sideLoaded.absolutePath}")
            val finalFile = modelFile()
            if (finalFile.exists()) finalFile.delete()
            sideLoaded.copyTo(finalFile, overwrite = true)
            onProgress(1.0)
            Log.i(TAG, "Side-loaded model installed successfully")
            return@withContext
        }

        val dir = modelsDir()
        val tempFile = File(dir, "$MODEL_FILE_NAME.tmp")
        val finalFile = modelFile()

        try {
            // Resume support: check existing partial download
            val existingBytes = if (tempFile.exists()) tempFile.length() else 0L

            val url = URL(MODEL_DOWNLOAD_URL)
            val connection = url.openConnection() as HttpURLConnection
            connection.connectTimeout = 30_000
            connection.readTimeout = 60_000
            connection.requestMethod = "GET"
            connection.instanceFollowRedirects = true

            // Request range if we have a partial download
            if (existingBytes > 0) {
                connection.setRequestProperty("Range", "bytes=$existingBytes-")
                Log.i(TAG, "Resuming download from byte $existingBytes")
            }

            connection.connect()

            val responseCode = connection.responseCode
            val isResume = responseCode == 206
            if (responseCode !in listOf(200, 206)) {
                throw RuntimeException("Download failed with HTTP $responseCode")
            }

            // If server doesn't support resume (200 instead of 206), start fresh
            val startOffset = if (isResume) existingBytes else 0L
            val contentLength = connection.contentLengthLong
            val totalBytes = if (isResume) startOffset + contentLength else contentLength
            Log.i(TAG, "Downloading model: totalBytes=$totalBytes, offset=$startOffset")

            if (startOffset > 0) {
                onProgress(startOffset.toDouble() / totalBytes.toDouble())
            }

            connection.inputStream.use { input ->
                // Append if resuming, overwrite if starting fresh
                FileOutputStream(tempFile, isResume).use { output ->
                    val buffer = ByteArray(32768)
                    var bytesRead: Int
                    var totalRead = startOffset

                    while (input.read(buffer).also { bytesRead = it } != -1) {
                        output.write(buffer, 0, bytesRead)
                        totalRead += bytesRead
                        if (totalBytes > 0) {
                            onProgress(totalRead.toDouble() / totalBytes.toDouble())
                        }
                    }
                }
            }

            // Move temp file to final location
            if (finalFile.exists()) finalFile.delete()
            tempFile.renameTo(finalFile)
            Log.i(TAG, "Model downloaded successfully")
        } catch (e: Exception) {
            // Keep partial download for resume — don't delete tempFile
            Log.w(TAG, "Download interrupted (${tempFile.length()} bytes saved for resume)", e)
            val friendlyMsg = when {
                e is java.net.UnknownHostException ->
                    "No internet connection. Copy $MODEL_FILE_NAME to device Download folder and retry, or connect to a network."
                e is java.net.SocketTimeoutException ->
                    "Download timed out. Tap Download to resume from where it left off."
                e is java.io.IOException ->
                    "Network error. Tap Download to resume from where it left off."
                else -> e.message ?: "Download failed"
            }
            throw RuntimeException(friendlyMsg, e)
        }
    }

    /**
     * Check common side-load locations for the model file.
     * Users can copy the GGUF file via ADB: adb push model.gguf /sdcard/Download/
     */
    private fun findSideLoadedModel(): File? {
        val searchDirs = listOf(
            "/sdcard/Download",
            "/sdcard/Downloads",
            "/storage/emulated/0/Download",
            "/storage/emulated/0/Downloads",
        )
        for (dir in searchDirs) {
            val file = File(dir, MODEL_FILE_NAME)
            if (file.exists() && file.length() > 1_000_000) {
                return file
            }
        }
        return null
    }

    // --- Prompt building ---

    fun buildPrompt(ocrText: String, jsonSchema: String): String {
        return """<|im_start|>system
You are a precise document data extraction assistant. Extract structured data from OCR text. Return ONLY compact JSON (no newlines, no extra spaces) matching the schema. Do not wrap in markdown. Do not explain./no_think<|im_end|>
<|im_start|>user
Extract data matching this JSON schema:
$jsonSchema

OCR TEXT:
$ocrText<|im_end|>
<|im_start|>assistant
"""
    }
}

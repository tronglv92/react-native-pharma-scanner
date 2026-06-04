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

    private const val MODEL_FILE_NAME = "Qwen3-1.7B-Q4_K_M.gguf"
    private const val MODEL_DOWNLOAD_URL =
        "https://huggingface.co/unsloth/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q4_K_M.gguf"

    // N_GPU_LAYERS: 0 for Android (CPU-only, no Metal)
    private const val N_GPU_LAYERS = 0

    private var nativeLibLoaded = false

    private fun ensureNativeLib() {
        if (!nativeLibLoaded) {
            System.loadLibrary("llama_bridge")
            nativeLibLoaded = true
        }
    }

    // JNI native methods
    private external fun nativeLoadModel(modelPath: String, nGpuLayers: Int): Boolean
    private external fun nativeGenerate(prompt: String, maxTokens: Int): String
    private external fun nativeUnloadModel()
    private external fun nativeIsLoaded(): Boolean

    // --- Model file paths ---

    private fun modelsDir(): File {
        val context = ActivityProvider.currentActivity
            ?: throw IllegalStateException("Activity not available")
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
        val result = nativeGenerate(prompt, 2048)
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

        val dir = modelsDir()
        val tempFile = File(dir, "$MODEL_FILE_NAME.tmp")
        val finalFile = modelFile()

        try {
            val url = URL(MODEL_DOWNLOAD_URL)
            val connection = url.openConnection() as HttpURLConnection
            connection.connectTimeout = 30_000
            connection.readTimeout = 60_000
            connection.requestMethod = "GET"
            // Follow redirects (HuggingFace may redirect)
            connection.instanceFollowRedirects = true
            connection.connect()

            val responseCode = connection.responseCode
            if (responseCode !in 200..299) {
                throw RuntimeException("Download failed with HTTP $responseCode")
            }

            val totalBytes = connection.contentLengthLong
            Log.i(TAG, "Downloading model: $totalBytes bytes")

            connection.inputStream.use { input ->
                FileOutputStream(tempFile).use { output ->
                    val buffer = ByteArray(8192)
                    var bytesRead: Int
                    var totalRead = 0L

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
            tempFile.delete()
            throw e
        }
    }

    // --- Prompt building ---

    fun buildPrompt(ocrText: String, jsonSchema: String): String {
        return """<|im_start|>system
You are a precise document data extraction assistant. Extract structured data from OCR text. Return ONLY valid JSON matching the schema. Do not include any explanation or markdown formatting./no_think<|im_end|>
<|im_start|>user
Extract data matching this JSON schema:
$jsonSchema

OCR TEXT:
$ocrText<|im_end|>
<|im_start|>assistant
"""
    }
}

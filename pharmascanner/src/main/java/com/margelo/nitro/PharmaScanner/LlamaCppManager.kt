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

    private const val MODEL_FILE_NAME = "Qwen2.5-VL-3B-Instruct-Q4_K_M.gguf"
    private const val MMPROJ_FILE_NAME = "mmproj-Qwen2.5-VL-3B-Instruct-f16.gguf"
    private const val MODEL_DOWNLOAD_URL =
        "https://huggingface.co/ggml-org/Qwen2.5-VL-3B-Instruct-GGUF/resolve/main/Qwen2.5-VL-3B-Instruct-Q4_K_M.gguf"
    private const val MMPROJ_DOWNLOAD_URL =
        "https://huggingface.co/ggml-org/Qwen2.5-VL-3B-Instruct-GGUF/resolve/main/mmproj-Qwen2.5-VL-3B-Instruct-f16.gguf"

    // Old model file to clean up on first run
    private const val OLD_MODEL_FILE_NAME = "Qwen3-0.6B-Q4_K_M.gguf"

    // N_GPU_LAYERS: 0 for Android (CPU-only, no Metal)
    private const val N_GPU_LAYERS = 0

    private var nativeLibLoaded = false

    private fun ensureNativeLib() {
        if (!nativeLibLoaded) {
            // Load shared library dependencies in order (BUILD_SHARED_LIBS=ON)
            System.loadLibrary("ggml-base")
            System.loadLibrary("ggml")
            System.loadLibrary("llama")
            System.loadLibrary("mtmd")
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
    private external fun nativeLoadModel(modelPath: String, mmprojPath: String, nGpuLayers: Int): Boolean
    private external fun nativeGenerateFromImage(prompt: String, imagePath: String, maxTokens: Int): String
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
    private fun mmprojFile(): File = File(modelsDir(), MMPROJ_FILE_NAME)

    // --- Public API ---

    val isModelDownloaded: Boolean
        get() = modelFile().exists() && mmprojFile().exists()

    val isModelLoaded: Boolean
        get() {
            ensureNativeLib()
            return nativeIsLoaded()
        }

    fun loadModel() {
        ensureNativeLib()
        if (isModelLoaded) return
        if (!isModelDownloaded) {
            throw IllegalStateException("Model files not found. Please download the model first.")
        }
        val success = nativeLoadModel(modelFile().absolutePath, mmprojFile().absolutePath, N_GPU_LAYERS)
        if (!success) {
            throw RuntimeException("Failed to load the vision model files.")
        }
        Log.i(TAG, "Vision model loaded successfully")
    }

    suspend fun generateFromImage(prompt: String, imagePath: String): String = withContext(Dispatchers.Default) {
        ensureNativeLib()
        if (!nativeIsLoaded()) {
            throw IllegalStateException("Model is not loaded. Call loadModel() first.")
        }
        val result = nativeGenerateFromImage(prompt, imagePath, 512)
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

        // One-time cleanup: delete old Qwen3 model file if present
        cleanupOldModel()

        // Check if both files were side-loaded to the Download folder
        val sideLoadedModel = findSideLoadedFile(MODEL_FILE_NAME)
        val sideLoadedMmproj = findSideLoadedFile(MMPROJ_FILE_NAME)
        if (sideLoadedModel != null && sideLoadedMmproj != null) {
            Log.i(TAG, "Found side-loaded model files")
            val finalModel = modelFile()
            val finalMmproj = mmprojFile()
            if (finalModel.exists()) finalModel.delete()
            if (finalMmproj.exists()) finalMmproj.delete()
            sideLoadedModel.copyTo(finalModel, overwrite = true)
            sideLoadedMmproj.copyTo(finalMmproj, overwrite = true)
            onProgress(1.0)
            Log.i(TAG, "Side-loaded model files installed successfully")
            return@withContext
        }

        // Download text model (59% of total progress — 1.93 GB / 3.27 GB)
        if (!modelFile().exists()) {
            downloadFile(MODEL_DOWNLOAD_URL, MODEL_FILE_NAME) { fileProgress ->
                onProgress(fileProgress * 0.59)
            }
        } else {
            onProgress(0.59)
        }

        // Download mmproj (41% of total progress — 1.34 GB / 3.27 GB)
        if (!mmprojFile().exists()) {
            downloadFile(MMPROJ_DOWNLOAD_URL, MMPROJ_FILE_NAME) { fileProgress ->
                onProgress(0.59 + fileProgress * 0.41)
            }
        } else {
            onProgress(1.0)
        }
    }

    private fun cleanupOldModel() {
        val oldFile = File(modelsDir(), OLD_MODEL_FILE_NAME)
        if (oldFile.exists()) {
            Log.i(TAG, "Deleting old model file: ${oldFile.name}")
            oldFile.delete()
        }
        // Also clean up any old temp files
        val oldTemp = File(modelsDir(), "$OLD_MODEL_FILE_NAME.tmp")
        if (oldTemp.exists()) {
            oldTemp.delete()
        }
    }

    private fun downloadFile(downloadUrl: String, fileName: String, onProgress: (Double) -> Unit) {
        val dir = modelsDir()
        val tempFile = File(dir, "$fileName.tmp")
        val finalFile = File(dir, fileName)

        try {
            // Resume support: check existing partial download
            val existingBytes = if (tempFile.exists()) tempFile.length() else 0L

            val url = URL(downloadUrl)
            val connection = url.openConnection() as HttpURLConnection
            connection.connectTimeout = 30_000
            connection.readTimeout = 60_000
            connection.requestMethod = "GET"
            connection.instanceFollowRedirects = true

            // Request range if we have a partial download
            if (existingBytes > 0) {
                connection.setRequestProperty("Range", "bytes=$existingBytes-")
                Log.i(TAG, "Resuming download of $fileName from byte $existingBytes")
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
            Log.i(TAG, "Downloading $fileName: totalBytes=$totalBytes, offset=$startOffset")

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
            Log.i(TAG, "$fileName downloaded successfully")
        } catch (e: Exception) {
            // Keep partial download for resume — don't delete tempFile
            Log.w(TAG, "Download of $fileName interrupted (${tempFile.length()} bytes saved for resume)", e)
            val friendlyMsg = when {
                e is java.net.UnknownHostException ->
                    "No internet connection. Copy $MODEL_FILE_NAME and $MMPROJ_FILE_NAME to device Download folder and retry, or connect to a network."
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
     * Check common side-load locations for a model file.
     * Users can copy GGUF files via ADB: adb push *.gguf /sdcard/Download/
     */
    private fun findSideLoadedFile(fileName: String): File? {
        val searchDirs = listOf(
            "/sdcard/Download",
            "/sdcard/Downloads",
            "/storage/emulated/0/Download",
            "/storage/emulated/0/Downloads",
        )
        for (dir in searchDirs) {
            val file = File(dir, fileName)
            if (file.exists() && file.length() > 1_000_000) {
                return file
            }
        }
        return null
    }

    // --- Prompt building ---

    fun buildVisionPrompt(documentType: String, jsonSchema: String): String {
        return """<|im_start|>system
You are a precise document data extraction assistant. Extract structured data from the document image. Return ONLY compact JSON (no newlines, no extra spaces) matching the schema. Do not wrap in markdown. Do not explain.<|im_end|>
<|im_start|>user
<__media__>
Extract data matching this JSON schema:
$jsonSchema<|im_end|>
<|im_start|>assistant
"""
    }
}

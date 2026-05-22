package com.margelo.nitro.PharmaScanner

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.ComponentActivity
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat

object PermissionHelper {

    fun requestCameraPermission(activity: ComponentActivity, callback: (Boolean) -> Unit) {
        val alreadyGranted = ContextCompat.checkSelfPermission(
            activity, Manifest.permission.CAMERA
        ) == PackageManager.PERMISSION_GRANTED

        if (alreadyGranted) {
            callback(true)
            return
        }

        val key = "camera_permission_${System.nanoTime()}"
        var launcher: ActivityResultLauncher<String>? = null

        launcher = activity.activityResultRegistry.register(
            key,
            ActivityResultContracts.RequestPermission()
        ) { granted ->
            launcher?.unregister()
            callback(granted)
        }

        launcher.launch(Manifest.permission.CAMERA)
    }
}

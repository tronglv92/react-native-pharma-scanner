package com.margelo.nitro.PharmaScanner

import android.app.Activity
import android.app.Application
import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.net.Uri
import android.os.Bundle
import java.lang.ref.WeakReference

object ActivityProvider {

    private var activityRef: WeakReference<Activity>? = null
    private var appContext: Context? = null
    @Volatile
    private var initialized = false

    val currentActivity: Activity?
        get() = activityRef?.get()

    /**
     * Application context — always available after init().
     * Use this for filesystem operations (filesDir, cacheDir, etc.)
     * that don't require an Activity.
     */
    val applicationContext: Context
        get() = appContext ?: throw IllegalStateException("ActivityProvider not initialized.")

    fun init(application: Application) {
        if (initialized) return
        initialized = true
        appContext = application.applicationContext
        application.registerActivityLifecycleCallbacks(object : Application.ActivityLifecycleCallbacks {
            override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {
                activityRef = WeakReference(activity)
            }
            override fun onActivityStarted(activity: Activity) {
                activityRef = WeakReference(activity)
            }
            override fun onActivityResumed(activity: Activity) {
                activityRef = WeakReference(activity)
            }

            override fun onActivityPaused(activity: Activity) {
                if (activityRef?.get() === activity) {
                    activityRef = null
                }
            }

            override fun onActivityStopped(activity: Activity) {}
            override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) {}
            override fun onActivityDestroyed(activity: Activity) {
                if (activityRef?.get() === activity) {
                    activityRef = null
                }
            }
        })
    }
}

/**
 * Auto-initializes ActivityProvider without requiring the host app
 * to call init() manually. Registered via AndroidManifest.
 */
class ActivityProviderInitializer : ContentProvider() {
    override fun onCreate(): Boolean {
        val app = context?.applicationContext as? Application ?: return false
        ActivityProvider.init(app)
        return true
    }
    override fun query(uri: Uri, proj: Array<String>?, sel: String?, selArgs: Array<String>?, sort: String?): Cursor? = null
    override fun getType(uri: Uri): String? = null
    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, sel: String?, selArgs: Array<String>?): Int = 0
    override fun update(uri: Uri, values: ContentValues?, sel: String?, selArgs: Array<String>?): Int = 0
}

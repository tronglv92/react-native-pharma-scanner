package com.margelo.nitro.PharmaScanner

import android.app.Activity
import android.app.Application
import android.content.Context
import android.os.Bundle
import java.lang.ref.WeakReference

object ActivityProvider {

    private var activityRef: WeakReference<Activity>? = null
    private var appContext: Context? = null

    val currentActivity: Activity?
        get() = activityRef?.get()

    /**
     * Application context — always available after init().
     * Use this for filesystem operations (filesDir, cacheDir, etc.)
     * that don't require an Activity.
     */
    val applicationContext: Context
        get() = appContext ?: throw IllegalStateException("ActivityProvider not initialized. Call init() from Application.onCreate().")

    fun init(application: Application) {
        appContext = application.applicationContext
        application.registerActivityLifecycleCallbacks(object : Application.ActivityLifecycleCallbacks {
            override fun onActivityResumed(activity: Activity) {
                activityRef = WeakReference(activity)
            }

            override fun onActivityPaused(activity: Activity) {
                if (activityRef?.get() === activity) {
                    activityRef = null
                }
            }

            override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {}
            override fun onActivityStarted(activity: Activity) {}
            override fun onActivityStopped(activity: Activity) {}
            override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) {}
            override fun onActivityDestroyed(activity: Activity) {}
        })
    }
}

package com.example.vertisignage

import android.app.Activity
import android.app.ActivityManager
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.os.Build

class DeviceOwnerPolicyManager(private val context: Context) {
    private val dpm = context.getSystemService(DevicePolicyManager::class.java)
    private val admin = ComponentName(context, VertiDeviceAdminReceiver::class.java)

    fun isDeviceOwner(): Boolean = dpm.isDeviceOwnerApp(context.packageName)

    fun applyKioskPolicies(): Boolean {
        return try {
            if (!isDeviceOwner()) {
                false
            } else {
                dpm.setLockTaskPackages(admin, arrayOf(context.packageName))
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    dpm.setLockTaskFeatures(admin, DevicePolicyManager.LOCK_TASK_FEATURE_NONE)
                }
                dpm.addUserRestriction(admin, android.os.UserManager.DISALLOW_SAFE_BOOT)
                dpm.addUserRestriction(admin, android.os.UserManager.DISALLOW_FACTORY_RESET)
                dpm.addUserRestriction(admin, android.os.UserManager.DISALLOW_ADD_USER)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    dpm.setStatusBarDisabled(admin, true)
                    dpm.setKeyguardDisabled(admin, true)
                }
                true
            }
        } catch (_: Exception) {
            false
        }
    }

    fun clearKioskPolicies(): Boolean {
        return try {
            if (!isDeviceOwner()) {
                false
            } else {
                dpm.setLockTaskPackages(admin, emptyArray())
                dpm.clearUserRestriction(admin, android.os.UserManager.DISALLOW_SAFE_BOOT)
                dpm.clearUserRestriction(admin, android.os.UserManager.DISALLOW_FACTORY_RESET)
                dpm.clearUserRestriction(admin, android.os.UserManager.DISALLOW_ADD_USER)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    dpm.setStatusBarDisabled(admin, false)
                    dpm.setKeyguardDisabled(admin, false)
                }
                true
            }
        } catch (_: Exception) {
            false
        }
    }

    /**
     * Classroom / multi-app mode on a Device Owner–provisioned tablet: release strict kiosk
     * restrictions so teachers can use other apps while VertiSignage stays installed as DO app.
     * Does not enter lock task (pair with Flutter `kioskLockTask == false`).
     */
    fun applyManagedClassroomPolicies(): Boolean = clearKioskPolicies()

    fun enterLockTask(activity: Activity): Boolean {
        return try {
            if (!applyKioskPolicies()) {
                false
            } else {
                activity.startLockTask()
                true
            }
        } catch (_: Exception) {
            false
        }
    }

    fun exitLockTask(activity: Activity): Boolean = try {
        activity.stopLockTask()
        clearKioskPolicies()
        true
    } catch (_: Exception) {
        false
    }

    fun isInLockTask(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val activityManager = context.getSystemService(ActivityManager::class.java)
            return activityManager.lockTaskModeState != ActivityManager.LOCK_TASK_MODE_NONE
        }
        @Suppress("DEPRECATION")
        return dpm.isLockTaskPermitted(context.packageName)
    }
}

package com.predidit.rekazumi

import android.app.Service
import android.app.ActivityManager
import android.app.Application
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.Message
import android.os.Messenger
import android.os.Process
import android.os.RemoteException
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class FrameGenerationValidationService : Service() {
    private val executor = Executors.newSingleThreadExecutor()
    private val validationStarted = AtomicBoolean(false)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val messenger = Messenger(IncomingHandler())

    private val nativeLoadError: String? by lazy {
        try {
            System.loadLibrary("rekazumi_framegen")
            null
        } catch (error: LinkageError) {
            error.javaClass.simpleName
        } catch (error: SecurityException) {
            error.javaClass.simpleName
        }
    }

    override fun onBind(intent: Intent?): IBinder = messenger.binder

    override fun onDestroy() {
        executor.shutdownNow()
        super.onDestroy()
    }

    private inner class IncomingHandler : Handler(Looper.getMainLooper()) {
        override fun handleMessage(message: Message) {
            if (message.what != FrameGenerationValidationProtocol.REQUEST_VALIDATE) {
                super.handleMessage(message)
                return
            }
            val reply = message.replyTo ?: return
            if (!isDedicatedValidationProcess()) {
                sendError(reply, "isolated_process_identity_mismatch")
                return
            }
            if (!validationStarted.compareAndSet(false, true)) {
                sendError(reply, "isolated_validation_already_started")
                return
            }

            sendStarted(reply)
            executor.execute {
                val loadError = nativeLoadError
                if (loadError != null) {
                    sendError(reply, "native_library_unavailable_$loadError")
                    scheduleProcessExit()
                    return@execute
                }
                try {
                    sendResult(reply, validateNativeVulkanOffscreen())
                } catch (error: LinkageError) {
                    sendError(reply, error.javaClass.simpleName)
                } catch (error: RuntimeException) {
                    sendError(reply, error.javaClass.simpleName)
                } finally {
                    scheduleProcessExit()
                }
            }
        }
    }

    private fun sendStarted(reply: Messenger) {
        val data = Bundle().apply {
            putInt(FrameGenerationValidationProtocol.KEY_PROCESS_ID, Process.myPid())
        }
        send(reply, FrameGenerationValidationProtocol.RESPONSE_STARTED, data)
    }

    private fun sendResult(reply: Messenger, nativeJson: String) {
        val data = Bundle().apply {
            putInt(FrameGenerationValidationProtocol.KEY_PROCESS_ID, Process.myPid())
            putString(FrameGenerationValidationProtocol.KEY_NATIVE_JSON, nativeJson)
        }
        send(reply, FrameGenerationValidationProtocol.RESPONSE_RESULT, data)
    }

    private fun sendError(reply: Messenger, error: String) {
        val data = Bundle().apply {
            putInt(FrameGenerationValidationProtocol.KEY_PROCESS_ID, Process.myPid())
            putString(FrameGenerationValidationProtocol.KEY_ERROR, error)
        }
        send(reply, FrameGenerationValidationProtocol.RESPONSE_ERROR, data)
    }

    private fun send(reply: Messenger, response: Int, data: Bundle) {
        try {
            reply.send(Message.obtain(null, response).apply { this.data = data })
        } catch (_: RemoteException) {
            scheduleProcessExit()
        }
    }

    private fun scheduleProcessExit() {
        mainHandler.postDelayed(
            { Process.killProcess(Process.myPid()) },
            PROCESS_EXIT_DELAY_MILLISECONDS,
        )
    }

    private fun isDedicatedValidationProcess(): Boolean {
        val currentProcessName = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            Application.getProcessName()
        } else {
            val activityManager = getSystemService(ACTIVITY_SERVICE) as ActivityManager
            activityManager.runningAppProcesses
                ?.firstOrNull { process -> process.pid == Process.myPid() }
                ?.processName
        }
        return currentProcessName == "$packageName:framegen_validation"
    }

    private external fun validateNativeVulkanOffscreen(): String

    private companion object {
        const val PROCESS_EXIT_DELAY_MILLISECONDS = 250L
    }
}

package com.predidit.rekazumi

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.Message
import android.os.Messenger
import android.os.Process
import android.os.RemoteException

internal data class IsolatedValidationResult(
    val nativeJson: String? = null,
    val error: String = "",
    val remoteProcessId: Int = 0,
)

internal class FrameGenerationValidationClient(
    context: Context,
    private val onComplete: (IsolatedValidationResult) -> Unit,
) {
    private val applicationContext = context.applicationContext
    private val mainHandler = Handler(Looper.getMainLooper())
    private val responseMessenger = Messenger(ResponseHandler())
    private var remoteProcessId = 0
    private var bound = false
    private var finished = false

    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
            if (finished || binder == null) {
                finish(error = "isolated_service_null_binding")
                return
            }
            try {
                Messenger(binder).send(
                    Message.obtain(
                        null,
                        FrameGenerationValidationProtocol.REQUEST_VALIDATE,
                    ).apply { replyTo = responseMessenger },
                )
            } catch (error: RemoteException) {
                finish(error = error.javaClass.simpleName)
            }
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            finish(error = "isolated_service_disconnected")
        }

        override fun onBindingDied(name: ComponentName?) {
            finish(error = "isolated_service_binding_died")
        }

        override fun onNullBinding(name: ComponentName?) {
            finish(error = "isolated_service_null_binding")
        }
    }

    private val timeout = Runnable {
        finish(error = "isolated_validation_timeout", killRemoteProcess = true)
    }

    fun start() {
        check(Looper.myLooper() == Looper.getMainLooper())
        val intent = Intent(
            applicationContext,
            FrameGenerationValidationService::class.java,
        )
        bound = applicationContext.bindService(
            intent,
            connection,
            Context.BIND_AUTO_CREATE,
        )
        if (!bound) {
            finish(error = "isolated_service_bind_failed")
            return
        }
        mainHandler.postDelayed(timeout, VALIDATION_TIMEOUT_MILLISECONDS)
    }

    fun cancel() {
        finish(
            error = "isolated_validation_cancelled",
            killRemoteProcess = true,
            deliverResult = false,
        )
    }

    private inner class ResponseHandler : Handler(Looper.getMainLooper()) {
        override fun handleMessage(message: Message) {
            when (message.what) {
                FrameGenerationValidationProtocol.RESPONSE_STARTED -> {
                    if (!updateRemoteProcessId(message)) {
                        finish(error = "isolated_process_id_invalid")
                    }
                }
                FrameGenerationValidationProtocol.RESPONSE_RESULT -> {
                    if (!updateRemoteProcessId(message)) {
                        finish(error = "isolated_process_id_invalid")
                        return
                    }
                    finish(
                        nativeJson = message.data.getString(
                            FrameGenerationValidationProtocol.KEY_NATIVE_JSON,
                        ),
                    )
                }
                FrameGenerationValidationProtocol.RESPONSE_ERROR -> {
                    if (!updateRemoteProcessId(message)) {
                        finish(error = "isolated_process_id_invalid")
                        return
                    }
                    finish(
                        error = message.data.getString(
                            FrameGenerationValidationProtocol.KEY_ERROR,
                        ) ?: "isolated_validation_unknown_error",
                    )
                }
                else -> super.handleMessage(message)
            }
        }
    }

    private fun updateRemoteProcessId(message: Message): Boolean {
        val processId = message.data.getInt(
            FrameGenerationValidationProtocol.KEY_PROCESS_ID,
            0,
        )
        if (processId <= 0 || processId == Process.myPid()) return false
        remoteProcessId = processId
        return true
    }

    private fun finish(
        nativeJson: String? = null,
        error: String = "",
        killRemoteProcess: Boolean = false,
        deliverResult: Boolean = true,
    ) {
        if (finished) return
        finished = true
        mainHandler.removeCallbacks(timeout)
        if (
            killRemoteProcess &&
            remoteProcessId > 0 &&
            remoteProcessId != Process.myPid()
        ) {
            Process.killProcess(remoteProcessId)
        }
        if (bound) {
            bound = false
            try {
                applicationContext.unbindService(connection)
            } catch (_: IllegalArgumentException) {
                // The remote process may have died between the callback and cleanup.
            }
        }
        if (deliverResult) {
            onComplete(
                IsolatedValidationResult(
                    nativeJson = nativeJson,
                    error = error,
                    remoteProcessId = remoteProcessId,
                ),
            )
        }
    }

    private companion object {
        const val VALIDATION_TIMEOUT_MILLISECONDS = 7_000L
    }
}

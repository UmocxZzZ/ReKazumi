package com.predidit.rekazumi

internal object FrameGenerationValidationProtocol {
    const val REQUEST_VALIDATE = 1
    const val RESPONSE_STARTED = 2
    const val RESPONSE_RESULT = 3
    const val RESPONSE_ERROR = 4

    const val KEY_PROCESS_ID = "processId"
    const val KEY_NATIVE_JSON = "nativeJson"
    const val KEY_ERROR = "error"
}

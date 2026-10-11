package com.example.voxa

import android.Manifest
import android.content.Intent
import android.net.Uri
import android.content.pm.PackageManager
import android.media.MediaRecorder
import android.os.Build
import androidx.core.app.ActivityCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channelName = "com.voxa/audio_recorder"
    private val microphoneRequestCode = 7214
    private var recorder: MediaRecorder? = null
    private var recordingFile: File? = null
    private var pendingStartResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MediaEditor(this).register(flutterEngine.dartExecutor.binaryMessenger)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.voxa/external_links")
            .setMethodCallHandler { call, result ->
                if (call.method != "open") {
                    result.notImplemented()
                } else {
                    try {
                        val uri = Uri.parse(call.argument<String>("url") ?: "")
                        require(uri.scheme in listOf("http", "https") && !uri.host.isNullOrEmpty())
                        startActivity(Intent(Intent.ACTION_VIEW, uri))
                        result.success(null)
                    } catch (error: Exception) {
                        result.error("link_failed", "No application could open this link.", null)
                    }
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> startRecording(result)
                    "stop" -> stopRecording(result)
                    "cancel" -> cancelRecording(result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun startRecording(result: MethodChannel.Result) {
        if (recorder != null) {
            result.error("already_recording", "A recording is already in progress.", null)
            return
        }
        if (ActivityCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            pendingStartResult = result
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.RECORD_AUDIO),
                microphoneRequestCode,
            )
            return
        }
        try {
            val file = File(cacheDir, "voxa_voice_${System.currentTimeMillis()}.m4a")
            val audioRecorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                MediaRecorder(this)
            } else {
                @Suppress("DEPRECATION")
                MediaRecorder()
            }
            audioRecorder.setAudioSource(MediaRecorder.AudioSource.MIC)
            audioRecorder.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            audioRecorder.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            audioRecorder.setAudioEncodingBitRate(128_000)
            audioRecorder.setAudioSamplingRate(44_100)
            audioRecorder.setOutputFile(file.absolutePath)
            audioRecorder.prepare()
            audioRecorder.start()
            recorder = audioRecorder
            recordingFile = file
            result.success(true)
        } catch (error: Exception) {
            recorder?.release()
            recorder = null
            recordingFile?.delete()
            recordingFile = null
            result.error("record_start_failed", error.message, null)
        }
    }

    private fun stopRecording(result: MethodChannel.Result) {
        val activeRecorder = recorder
        val file = recordingFile
        if (activeRecorder == null || file == null) {
            result.error("not_recording", "There is no active voice recording.", null)
            return
        }
        try {
            activeRecorder.stop()
            result.success(file.absolutePath)
        } catch (error: Exception) {
            file.delete()
            result.error("record_stop_failed", error.message, null)
        } finally {
            activeRecorder.release()
            recorder = null
            recordingFile = null
        }
    }

    private fun cancelRecording(result: MethodChannel.Result) {
        recorder?.let { activeRecorder ->
            runCatching { activeRecorder.stop() }
            activeRecorder.release()
        }
        recorder = null
        recordingFile?.delete()
        recordingFile = null
        result.success(null)
    }

    @Deprecated("Deprecated in Android")
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != microphoneRequestCode) return
        val result = pendingStartResult ?: return
        pendingStartResult = null
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            startRecording(result)
        } else {
            result.error("microphone_permission_denied", "Allow microphone access to record a voice message.", null)
        }
    }
}

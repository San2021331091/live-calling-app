package com.example.voxa

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.BitmapOverlay
import androidx.media3.effect.OverlayEffect
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.Transformer
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/** Exports actual trimmed/muted MP4s with the editor's transparent overlay. */
@UnstableApi
class MediaEditor(private val context: Context) {
    private var transformer: Transformer? = null
    private var overlayBitmap: Bitmap? = null

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, "com.voxa/media_editor").setMethodCallHandler { call, result ->
            if (call.method == "exportVideo") export(call, result) else result.notImplemented()
        }
    }

    private fun export(call: MethodCall, result: MethodChannel.Result) {
        if (transformer != null) {
            result.error("export_busy", "Another video is being exported.", null)
            return
        }
        val input = call.argument<String>("input")
        val start = call.argument<Number>("startMs")?.toLong() ?: 0L
        val end = call.argument<Number>("endMs")?.toLong() ?: 0L
        val width = call.argument<Number>("width")?.toInt() ?: 0
        val height = call.argument<Number>("height")?.toInt() ?: 0
        if (input == null || !File(input).isFile || start < 0 || end <= start ||
            width <= 0 || height <= 0 || width > 8192 || height > 8192) {
            result.error("invalid_edit", "Invalid source video or trim range.", null)
            return
        }
        val output = File(context.cacheDir, "voxa_edited_${System.nanoTime()}.mp4")
        try {
            val media = MediaItem.Builder()
                .setUri(Uri.fromFile(File(input)))
                .setClippingConfiguration(MediaItem.ClippingConfiguration.Builder()
                    .setStartPositionMs(start).setEndPositionMs(end).build())
                .build()
            val edited = EditedMediaItem.Builder(media)
                .setRemoveAudio(call.argument<Boolean>("mute") == true)
            call.argument<String>("overlay")?.let { path ->
                val decoded = BitmapFactory.decodeFile(path)
                    ?: throw IllegalArgumentException("Could not decode editor overlay.")
                val scaled = Bitmap.createScaledBitmap(decoded, width, height, true)
                if (scaled !== decoded) decoded.recycle()
                overlayBitmap = scaled
                edited.setEffects(Effects(emptyList(), listOf(
                    OverlayEffect(listOf(BitmapOverlay.createStaticBitmapOverlay(scaled)))
                )))
            }
            val exporter = Transformer.Builder(context)
                .setVideoMimeType(MimeTypes.VIDEO_H264)
                .setAudioMimeType(MimeTypes.AUDIO_AAC)
                .addListener(object : Transformer.Listener {
                    override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                        release()
                        if (output.isFile && output.length() > 0) result.success(output.absolutePath)
                        else result.error("empty_export", "Video encoder produced no output.", null)
                    }

                    override fun onError(composition: Composition, exportResult: ExportResult, exportException: ExportException) {
                        release()
                        output.delete()
                        result.error("video_export_failed", exportException.message, null)
                    }
                }).build()
            transformer = exporter
            exporter.start(edited.build(), output.absolutePath)
        } catch (error: Exception) {
            transformer?.cancel()
            release()
            output.delete()
            result.error("video_export_failed", error.message, null)
        }
    }

    private fun release() {
        transformer = null
        overlayBitmap?.recycle()
        overlayBitmap = null
    }
}

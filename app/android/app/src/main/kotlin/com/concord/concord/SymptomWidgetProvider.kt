package com.concord.concord

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.Color
import android.os.Build
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

class SymptomWidgetProvider : HomeWidgetProvider() {

  private fun resolveGradeColor(context: Context, grade: Int): Int {
    val resId =
        when (grade) {
          1 -> R.color.widget_grade_mild
          2 -> R.color.widget_grade_moderate
          3 -> R.color.widget_grade_severe
          else -> R.color.widget_grade_none
        }
    return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
      context.getColor(resId)
    } else {
      @Suppress("DEPRECATION") context.resources.getColor(resId)
    }
  }

  override fun onUpdate(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetIds: IntArray,
      widgetData: SharedPreferences,
  ) {
    val status =
        widgetData.getString("symptom_status", "Log today\u2019s symptoms")
            ?: "Log today\u2019s symptoms"
    val grade = widgetData.getInt("symptom_grade", -1)
    val gradeText = widgetData.getString("symptom_grade_text", "")
    val pendingCount = widgetData.getInt("pending_sync_count", 0)

    val launchIntent =
        context.packageManager.getLaunchIntentForPackage(context.packageName)?.apply {
          data = android.net.Uri.parse("concord://log")
        }

    val flags: Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
          PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        } else {
          PendingIntent.FLAG_UPDATE_CURRENT
        }

    val pendingIntent = PendingIntent.getActivity(context, 0, launchIntent, flags)

    for (appWidgetId in appWidgetIds) {
      val views = RemoteViews(context.packageName, R.layout.symptom_widget_layout)

      views.setTextViewText(R.id.widget_status, status)

      if (!gradeText.isNullOrBlank() && grade >= 0) {
        views.setTextViewText(R.id.widget_grade, gradeText)
        views.setViewVisibility(R.id.widget_grade, android.view.View.VISIBLE)
        views.setTextColor(R.id.widget_grade, resolveGradeColor(context, grade))
      } else {
        views.setViewVisibility(R.id.widget_grade, android.view.View.GONE)
      }

      if (pendingCount > 0) {
        views.setTextViewText(R.id.widget_pending_badge, "$pendingCount pending")
        views.setViewVisibility(R.id.widget_pending_badge, android.view.View.VISIBLE)
      } else {
        views.setViewVisibility(R.id.widget_pending_badge, android.view.View.GONE)
      }

      views.setOnClickPendingIntent(R.id.widget_container, pendingIntent)

      appWidgetManager.updateAppWidget(appWidgetId, views)
    }
  }
}

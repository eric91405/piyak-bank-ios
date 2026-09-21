package com.minseo.piyakbank

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import com.minseo.piyakbank.platform.PiyakViewModel
import com.minseo.piyakbank.platform.CsvExportRequest
import com.minseo.piyakbank.platform.CsvExportResult
import com.minseo.piyakbank.platform.CsvExportViewModel
import com.minseo.piyakbank.platform.ReminderScheduler
import com.minseo.piyakbank.ui.PiyakApp
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    private val vm: PiyakViewModel by viewModels()
    internal val csvExports: CsvExportViewModel by viewModels()
    internal val exportRequest = CsvExportRequest()
    private val notifications = registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        val permitted = granted && ReminderScheduler.notificationsAvailable(this)
        vm.updateNotifications(permitted)
        if (!permitted) Toast.makeText(this, "알림 없이도 모든 기능을 사용할 수 있어요.", Toast.LENGTH_LONG).show()
    }
    private val exportFile = registerForActivityResult(ActivityResultContracts.CreateDocument("text/csv")) { uri ->
        csvExports.start(uri, exportRequest.kind)
    }
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        exportRequest.restore(savedInstanceState)
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                csvExports.status.collect { state ->
                    val result = state.result ?: return@collect
                    csvExports.consume(result)
                    when (result) {
                        CsvExportResult.SAVED -> Toast.makeText(this@MainActivity, "CSV 파일을 저장했어요.", Toast.LENGTH_SHORT).show()
                        CsvExportResult.FAILED -> Toast.makeText(this@MainActivity, "파일을 저장하지 못했어요. 저장 위치와 공간을 확인해 주세요.", Toast.LENGTH_LONG).show()
                        CsvExportResult.CANCELLED -> Unit
                    }
                }
            }
        }
        enableEdgeToEdge()
        setContent { PiyakApp(vm, onExport = { kind ->
            if (csvExports.status.value.writing) Toast.makeText(this, "CSV 파일을 저장하고 있어요. 잠시 기다려 주세요.", Toast.LENGTH_SHORT).show()
            else {
                val request = exportRequest.select(kind)
                try { exportFile.launch(request.fileName) }
                catch (_: android.content.ActivityNotFoundException) { Toast.makeText(this, "파일 저장 앱을 찾지 못했어요.", Toast.LENGTH_LONG).show() }
            }
        }, onRequestNotifications = {
            if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) notifications.launch(Manifest.permission.POST_NOTIFICATIONS)
            else {
                val permitted = ReminderScheduler.notificationsAvailable(this)
                vm.updateNotifications(permitted)
                if (!permitted) Toast.makeText(this, "Android 설정에서 삐약뱅크 알림을 허용해 주세요.", Toast.LENGTH_LONG).show()
            }
        }) }
    }
    override fun onStart() { super.onStart(); vm.visible(true) }
    override fun onStop() { vm.visible(false); super.onStop() }
    override fun onSaveInstanceState(outState: Bundle) { exportRequest.save(outState); super.onSaveInstanceState(outState) }
}

package com.minseo.piyakbank

import android.Manifest
import android.app.NotificationManager
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.lifecycle.lifecycleScope
import com.minseo.piyakbank.platform.PiyakApplication
import com.minseo.piyakbank.platform.PiyakViewModel
import com.minseo.piyakbank.ui.PiyakApp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class MainActivity : ComponentActivity() {
    private val vm: PiyakViewModel by viewModels()
    private var exportKind = "records"
    private val notifications = registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        vm.updateNotifications(granted)
        if (!granted) Toast.makeText(this, "알림 없이도 모든 기능을 사용할 수 있어요.", Toast.LENGTH_LONG).show()
    }
    private val exportFile = registerForActivityResult(ActivityResultContracts.CreateDocument("text/csv")) { uri ->
        if (uri != null) lifecycleScope.launch {
            try {
                val repo = (application as PiyakApplication).repository
                withContext(Dispatchers.IO) {
                    val content = repo.export(exportKind)
                    val stream = contentResolver.openOutputStream(uri, "wt") ?: error("파일을 열지 못했어요.")
                    stream.bufferedWriter(Charsets.UTF_8).use { it.write(content) }
                }
                Toast.makeText(this@MainActivity, "CSV 파일을 저장했어요.", Toast.LENGTH_SHORT).show()
            } catch (_: Exception) { Toast.makeText(this@MainActivity, "파일을 저장하지 못했어요. 저장 위치와 공간을 확인해 주세요.", Toast.LENGTH_LONG).show() }
        }
    }
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        exportKind = savedInstanceState?.getString("exportKind") ?: "records"
        enableEdgeToEdge()
        setContent { PiyakApp(vm, onExport = { kind ->
            exportKind = kind
            exportFile.launch(if (kind == "points") "삐약뱅크_포인트.csv" else "삐약뱅크_근무기록.csv")
        }, onRequestNotifications = {
            if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) notifications.launch(Manifest.permission.POST_NOTIFICATIONS)
            else {
                val permitted = getSystemService(NotificationManager::class.java).areNotificationsEnabled()
                vm.updateNotifications(permitted)
                if (!permitted) Toast.makeText(this, "Android 설정에서 삐약뱅크 알림을 허용해 주세요.", Toast.LENGTH_LONG).show()
            }
        }) }
    }
    override fun onStart() { super.onStart(); vm.visible(true) }
    override fun onStop() { vm.visible(false); super.onStop() }
    override fun onSaveInstanceState(outState: Bundle) { outState.putString("exportKind", exportKind); super.onSaveInstanceState(outState) }
}

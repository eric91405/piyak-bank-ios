package com.minseo.piyakbank.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.minseo.piyakbank.core.*
import com.minseo.piyakbank.platform.PiyakViewModel
import com.minseo.piyakbank.platform.UiState

@Composable
internal fun ShopScreen(ui: UiState, viewModel: PiyakViewModel) {
    val data = ui.data ?: return
    var category by rememberSaveable { mutableIntStateOf(0) }
    var slot by rememberSaveable { mutableStateOf<String?>(null) }
    var selected by rememberSaveable { mutableStateOf<String?>(null) }
    val categories = listOf("모두", "우리 방", "삐약이", "보유함")
    val owned = remember(data.owned) { data.owned.associateBy { it.catalogId } }
    val slots = DecorSlot.entries.filter { category != 1 && category != 2 || it.isRoom == (category == 1) }
    val items = remember(category, slot, owned) { Catalog.items.filter {
        (category != 1 || it.slot.isRoom) && (category != 2 || !it.slot.isRoom) &&
            (category != 3 || owned.containsKey(it.id)) && (slot == null || it.slot.name == slot)
    } }
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.TopCenter) {
        LazyVerticalGrid(
            columns = GridCells.Adaptive(145.dp),
            modifier = Modifier.widthIn(max = 1120.dp).fillMaxSize(),
            contentPadding = PaddingValues(20.dp),
            horizontalArrangement = Arrangement.spacedBy(14.dp), verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            item(span = { GridItemSpan(maxLineSpan) }) { ScreenHeading("취향이 자라는 방", "매일의 시간이 작은 선물로") { PointBadge(DomainEngine.balance(data)) } }
            item(span = { GridItemSpan(maxLineSpan) }) {
                GameCard(color = MaterialTheme.colorScheme.secondaryContainer) {
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Rounded.AutoAwesome, null, Modifier.size(28.dp), tint = MaterialTheme.colorScheme.onSecondaryContainer)
                        Column {
                            Text("하나씩, 우리답게", style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.onSecondaryContainer)
                            Text("아이템을 눌러 3D 방에서 미리 입혀 보세요.\n꾸미기 포인트는 근무로만 모아요.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSecondaryContainer)
                        }
                    }
                }
            }
            item(span = { GridItemSpan(maxLineSpan) }) {
                LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    items(categories.indices.toList()) { index ->
                        FilterChip(selected = category == index, onClick = { category = index; slot = null }, label = { Text(categories[index]) }, leadingIcon = if (category == index) ({ Icon(Icons.Rounded.Check, null, Modifier.size(17.dp)) }) else null)
                    }
                }
            }
            item(span = { GridItemSpan(maxLineSpan) }) {
                LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    item { FilterChip(selected = slot == null, onClick = { slot = null }, label = { Text("전체 종류") }) }
                    items(slots) { value -> FilterChip(selected = slot == value.name, onClick = { slot = value.name }, label = { Text(value.label) }, leadingIcon = { Icon(slotIcon(value), null, Modifier.size(17.dp)) }) }
                }
            }
            item(span = { GridItemSpan(maxLineSpan) }) { Text("${items.size}개의 작은 취향", style = MaterialTheme.typography.titleMedium) }
            if (items.isEmpty()) item(span = { GridItemSpan(maxLineSpan) }) {
                GameCard {
                    Icon(Icons.Rounded.Inventory2, null, Modifier.size(34.dp))
                    Text("아직 비어 있는 보유함이에요", style = MaterialTheme.typography.titleMedium)
                    Text("마음에 드는 아이템을 모아 나만의 방을 만들어 보세요.", style = MaterialTheme.typography.bodyMedium)
                }
            }
            items(items, key = { it.id }) { item ->
                val ownership = owned[item.id]
                Surface(shape = RoundedCornerShape(23.dp), tonalElevation = 1.dp, color = MaterialTheme.colorScheme.surface, modifier = Modifier.fillMaxWidth().clickable { selected = item.id }.semantics(mergeDescendants = true) {
                    contentDescription = "${item.name}, ${item.slot.label}, ${if (ownership?.equipped == true) "장착 중" else if (ownership != null) "보유 중" else item.price.commas() + " 포인트"}. 미리보기"
                }) {
                    Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(9.dp)) {
                        ItemThumbnail(item.id, item.name, Modifier.fillMaxWidth().aspectRatio(1f))
                        Text(item.slot.label, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Text(item.name, style = MaterialTheme.typography.titleMedium)
                        Text(if (ownership?.equipped == true) "✓ 장착 중" else if (ownership != null) "보유 중" else item.price.toLong().points(), style = MaterialTheme.typography.labelLarge, color = if (ownership?.equipped == true) MaterialTheme.colorScheme.tertiary else MaterialTheme.colorScheme.primary)
                    }
                }
            }
        }
    }
    selected?.let { id -> Catalog.items.find { it.id == id }?.let { item ->
        ItemDetail(item, ui, viewModel, onDismiss = { selected = null })
    } }
}

@Composable
private fun ItemDetail(item: CatalogItem, ui: UiState, viewModel: PiyakViewModel, onDismiss: () -> Unit) {
    val data = ui.data ?: return
    val ownership = data.owned.find { it.catalogId == item.id }
    val balance = DomainEngine.balance(data)
    var confirmPurchase by rememberSaveable(item.id) { mutableStateOf(false) }
    var submittedAt by rememberSaveable(item.id) { mutableStateOf<Long?>(null) }
    ActionCompletion(ui, submittedAt) { confirmPurchase = false; submittedAt = null }
    Dialog(onDismissRequest = { if (!ui.busy) onDismiss() }, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Surface(modifier = Modifier.padding(14.dp).widthIn(max = 650.dp).fillMaxWidth().fillMaxHeight(.94f), shape = RoundedCornerShape(30.dp), color = MaterialTheme.colorScheme.background) {
            Column {
                Row(Modifier.fillMaxWidth().padding(start = 22.dp, top = 10.dp, end = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text("아이템 미리보기", style = MaterialTheme.typography.titleLarge, modifier = Modifier.weight(1f))
                    IconButton(onClick = onDismiss, enabled = !ui.busy) { Icon(Icons.Rounded.Close, "미리보기 닫기") }
                }
                Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(18.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
                    Room(ui, previewItemId = item.id)
                    Row(horizontalArrangement = Arrangement.spacedBy(16.dp), verticalAlignment = Alignment.CenterVertically) {
                        ItemThumbnail(item.id, item.name, Modifier.size(88.dp))
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            Text(item.slot.label, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            Text(item.name, style = MaterialTheme.typography.headlineMedium)
                            Text(if (ownership != null) "내 보유 아이템" else item.price.toLong().points(), style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.primary)
                        }
                    }
                    InfoText(if (item.slot.isRoom) "방의 ${item.slot.label} 자리에 놓아요. 같은 종류는 한 번에 하나만 장착할 수 있어요." else "삐약이의 ${item.slot.label}을 바꿔요. 같은 종류는 한 번에 하나만 장착할 수 있어요.")
                    ErrorText(ui.error)
                }
                Surface(color = MaterialTheme.colorScheme.surface, shadowElevation = 3.dp) {
                    Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        Text("내 포인트 ${balance.points()}", style = MaterialTheme.typography.bodySmall)
                        when {
                            ownership?.equipped == true -> OutlinedButton(onClick = { submittedAt = ui.actionRevision; viewModel.unequip(item.slot) }, enabled = !ui.busy, modifier = Modifier.fillMaxWidth().heightIn(min = 52.dp)) { Text("장착 해제") }
                            ownership != null -> Button(onClick = { submittedAt = ui.actionRevision; viewModel.equip(item.id) }, enabled = !ui.busy, modifier = Modifier.fillMaxWidth().heightIn(min = 52.dp)) { Text("우리 방에 장착하기") }
                            else -> Button(onClick = { confirmPurchase = true }, enabled = balance >= item.price && !ui.busy, modifier = Modifier.fillMaxWidth().heightIn(min = 52.dp)) {
                                Text(if (balance < item.price) "${(item.price - balance).points()} 더 필요해요" else "${item.price.toLong().points()}로 구매")
                            }
                        }
                        if (ownership == null) Text("실제 돈을 사용하지 않아요. 구매 후 아이템은 보유함에서 언제든 장착할 수 있어요.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
    }
    if (confirmPurchase) AlertDialog(
        onDismissRequest = { if (!ui.busy) confirmPurchase = false },
        title = { Text("${item.name}을 구매할까요?") },
        text = { Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text("${item.price.toLong().points()}를 사용해요. 구매 후 남는 포인트는 ${(balance - item.price).coerceAtLeast(0).points()}예요.")
            Text("아이템은 계속 보유할 수 있고, 구매로 레벨이 내려가지 않아요.")
            ErrorText(ui.error)
        } },
        confirmButton = { Button(onClick = { submittedAt = ui.actionRevision; viewModel.purchase(item.id) }, enabled = !ui.busy && balance >= item.price && ownership == null) { Text("구매하기") } },
        dismissButton = { TextButton(onClick = { confirmPurchase = false }, enabled = !ui.busy) { Text("취소") } },
    )
}

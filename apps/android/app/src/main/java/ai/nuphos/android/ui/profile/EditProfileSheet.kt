package ai.nuphos.android.ui.profile

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import ai.nuphos.android.model.NuphosUser
import ai.nuphos.android.model.profileValidationError
import ai.nuphos.android.ui.LocalAuthSession
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EditProfileSheet(user: NuphosUser, onDismiss: () -> Unit) {
    val auth = LocalAuthSession.current
    val scope = rememberCoroutineScope()
    var busy by remember(user.id) { mutableStateOf(false) }
    var error by remember(user.id) { mutableStateOf<String?>(null) }
    ModalBottomSheet(onDismissRequest = { if (!busy) onDismiss() },
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = MaterialTheme.colorScheme.background) {
        EditProfileForm(user, busy, error, onDismiss = onDismiss, onSave = { name, username, avatar ->
            error = profileValidationError(name, username, avatar)
            if (!busy && error == null && auth.user?.id == user.id) {
                busy = true
                val token = auth.token
                val generation = auth.generation
                scope.launch {
                    if (auth.token != token || auth.generation != generation || auth.user?.id != user.id) return@launch
                    val saved = auth.updateProfile(name.trim(), username.trim(), avatar.trim())
                    if (auth.token != token || auth.generation != generation || auth.user?.id != user.id) return@launch
                    busy = false
                    if (saved) onDismiss() else error = auth.profileError ?: "We could not save your profile. Please try again."
                }
            }
        })
    }
}

@Composable
internal fun EditProfileForm(user: NuphosUser, busy: Boolean, error: String?,
    onDismiss: () -> Unit, onSave: (String, String, String) -> Unit) {
    var name by rememberSaveable(user.id) { mutableStateOf(user.name) }
    var username by rememberSaveable(user.id) { mutableStateOf(user.username) }
    var avatar by rememberSaveable(user.id) { mutableStateOf(user.avatarURL) }
    Column(Modifier.fillMaxWidth().imePadding()) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = onDismiss, enabled = !busy) { Text("Cancel") }
            Text("Edit profile", style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f).padding(horizontal = 8.dp))
            TextButton(onClick = { if (!busy) onSave(name, username, avatar) },
                enabled = !busy && profileValidationError(name, username, avatar) == null) { Text(if (busy) "Saving…" else "Save") }
        }
        Column(Modifier.fillMaxWidth().weight(1f, fill = false).verticalScroll(rememberScrollState()).padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text("Profile", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
            OutlinedTextField(name, { name = it }, label = { Text("Name") }, enabled = !busy, modifier = Modifier.fillMaxWidth())
            OutlinedTextField(username, { username = it }, label = { Text("Username") }, enabled = !busy, modifier = Modifier.fillMaxWidth())
            OutlinedTextField(avatar, { avatar = it }, label = { Text("Profile image URL (optional)") }, singleLine = true, enabled = !busy, modifier = Modifier.fillMaxWidth())
            Text("Use an existing Google profile image URL, or leave this empty for your initials.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
        }
    }
}

package ai.nuphos.android.ui.profile

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Surface
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import ai.nuphos.android.model.NuphosUser
import ai.nuphos.android.ui.LocalAuthSession
import ai.nuphos.android.ui.components.NuphosAvatar

@Composable
internal fun BaselineProfileContent(
    user: NuphosUser,
    canWithdraw: Boolean,
    consentBusy: Boolean,
    consentError: String?,
    onEdit: () -> Unit,
    onPrivacy: () -> Unit,
    onWithdraw: () -> Unit,
    onDeletion: () -> Unit,
    onSignOut: () -> Unit,
    voiceSettings: @Composable () -> Unit,
) {
        Column(
            Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 24.dp, vertical = 8.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            NuphosAvatar(user, size = 84.dp)
            Spacer(Modifier.height(14.dp))
            Text(user.displayName, style = MaterialTheme.typography.headlineSmall)
            if (user.username.isNotEmpty()) {
                Text("@${user.username}", style = MaterialTheme.typography.bodyMedium, fontFamily = FontFamily.Monospace, color = MaterialTheme.colorScheme.primary)
            }
            Text(user.email, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(Modifier.height(24.dp))
            ai.nuphos.android.ui.components.TechnicalDetails(user.id) {
                Info("User ID", user.id, mono = true)
            }
            HorizontalDivider(Modifier.padding(vertical = 16.dp))
            TextButton(onClick = onEdit, modifier = Modifier.fillMaxWidth()) { Text("Edit profile") }
            TextButton(onClick = onPrivacy, modifier = Modifier.fillMaxWidth()) { Text("Privacy policy") }
            HorizontalDivider(Modifier.padding(vertical = 12.dp))
            voiceSettings()
            HorizontalDivider(Modifier.padding(vertical = 12.dp))
            Text("Account actions", style = MaterialTheme.typography.titleSmall)
            TextButton(onClick = onDeletion, modifier = Modifier.fillMaxWidth()) { Text("Account deletion request") }
            if (canWithdraw) {
                TextButton(onClick = onWithdraw, enabled = !consentBusy, modifier = Modifier.fillMaxWidth()) { Text("Withdraw AI sharing consent") }
            }
            consentError?.let { Text(it, color = MaterialTheme.colorScheme.error) }
            TextButton(onClick = onSignOut, modifier = Modifier.fillMaxWidth()) {
                Text("Sign out", color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.titleMedium)
            }
            Spacer(Modifier.height(24.dp))
        }
}

@Composable
private fun Info(label: String, value: String, mono: Boolean = false) {
    Column(Modifier.fillMaxWidth().padding(vertical = 8.dp)) {
        Text(label.uppercase(), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.outline)
        Text(
            value.ifEmpty { "—" },
            style = MaterialTheme.typography.bodyLarge,
            fontFamily = if (mono) FontFamily.Monospace else FontFamily.Default,
            color = if (value.isEmpty()) MaterialTheme.colorScheme.outline else MaterialTheme.colorScheme.onSurface,
        )
    }
}

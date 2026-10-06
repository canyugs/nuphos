package ai.nuphos.android.ui.agent

import android.content.ActivityNotFoundException
import android.net.Uri
import androidx.browser.customtabs.CustomTabsIntent
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import ai.nuphos.android.data.runtimeHttpsUrl
import ai.nuphos.android.session.RuntimeSetupStore

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RuntimeSetupSheet(store: RuntimeSetupStore, onDismiss: () -> Unit,
    launchBrowser: ((String) -> Unit)? = null) {
    var label by remember { mutableStateOf("") }
    var provider by remember { mutableStateOf("codex") }
    var code by remember { mutableStateOf("") }
    var browserError by remember { mutableStateOf(false) }
    val context = LocalContext.current
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val state = store.state
    val selection = store.selection
    DisposableEffect(store, lifecycle) {
        store.open()
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) store.setForeground(true)
            if (event == Lifecycle.Event.ON_PAUSE) { code = ""; store.setForeground(false) }
        }
        lifecycle.addObserver(observer)
        store.setForeground(lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED))
        onDispose {
            code = ""; store.close(); lifecycle.removeObserver(observer)
        }
    }
    LaunchedEffect(state.attempt?.attemptId, state.attempt?.state, state.attemptMismatch, selection.selectedId, selection.selected?.provider, selection.selected?.status, selection.selected?.kind) { code = ""; browserError = false }
    ModalBottomSheet(onDismissRequest = { code = ""; onDismiss() }, properties = ModalBottomSheetProperties(securePolicy = androidx.compose.ui.window.SecureFlagPolicy.SecureOn)) {
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text("Set up an Agent", style = MaterialTheme.typography.headlineSmall)
            Text("Choose an Agent for new chats. Existing chats keep their saved runtime. Active registration does not confirm provider readiness.")
            state.error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
            state.message?.let { Text(it) }
            if (state.busy) LinearProgressIndicator(Modifier.fillMaxWidth())
            if (selection.reselectionRequired) Text("The selected Agent is unavailable. Select a saved active Agent before starting a new chat.")
            selection.catalog.forEach { runtime ->
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Column(Modifier.weight(1f)) { Text(runtime.label); Text("${runtime.provider} · ${runtime.kind} · ${runtime.status}") }
                    TextButton(onClick = { code = ""; store.select(runtime.id) }, enabled = !state.busy && state.catalogLoaded && runtime.selectable) {
                        Text(if (selection.selectedId == runtime.id) "Selected ${runtime.label}" else "Use ${runtime.label}")
                    }
                }
            }
            if (state.catalogLoaded && selection.catalog.isEmpty()) Text("No saved Agents.")
            OutlinedButton(onClick = { store.refresh() }, enabled = !state.busy) { Text("Refresh Agents") }
            if (store.canAdminister) {
                Text("Managed Agent", style = MaterialTheme.typography.titleMedium)
                Text("Creation can allocate resources. Provider sign-in is a separate step.")
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    FilterChip(provider == "codex", onClick = { provider = "codex" }, label = { Text("Codex") })
                    FilterChip(provider == "claude-code", onClick = { provider = "claude-code" }, label = { Text("Claude Code") })
                }
                OutlinedTextField(label, { label = it }, label = { Text("Agent label (optional)") }, enabled = !state.busy && !selection.createReview, singleLine = true)
                Button(onClick = { store.create(provider, label.trim().takeIf { it.isNotEmpty() }) },
                    enabled = !state.busy && !selection.createReview && label.trim().length <= 120) { Text("Create Agent") }
                if (selection.createReview) {
                    Text("Creation is unconfirmed. Closing does not undo a saved Agent.")
                    OutlinedButton(onClick = store::confirmCreateReviewed, enabled = !state.busy && state.catalogLoaded) { Text("I reviewed saved Agents") }
                }
                if (selection.selected?.kind == "managed") {
                    Button(onClick = store::startLogin, enabled = !state.busy && !selection.loginReview) { Text("Start provider sign-in") }
                    if (selection.loginReview) {
                        if (selection.loginRuntimeId != selection.selectedId) Text("Another Agent has an unconfirmed sign-in. Select that Agent and refresh its sign-in before starting another.")
                        val attempt = state.attempt
                        Text("Sign-in: ${attempt?.state ?: "unconfirmed"}")
                        OutlinedButton(onClick = store::refreshLogin, enabled = !state.busy) { Text("Refresh sign-in") }
                        if (attempt?.state == "awaiting_authorization" && attempt.valid(System.currentTimeMillis()) && !state.attemptMismatch && state.loginReconciled) {
                            attempt.userCode?.let { Text("Provider code: $it") }
                            attempt.browserUrl?.let { url ->
                                OutlinedButton(onClick = {
                                    val currentUrl = store.authorizationUrlFor(attempt.attemptId)
                                    if (currentUrl != null && currentUrl == url && runtimeHttpsUrl(currentUrl)) {
                                        try { if (launchBrowser != null) launchBrowser(url) else CustomTabsIntent.Builder().setShareState(CustomTabsIntent.SHARE_STATE_OFF).build().launchUrl(context, Uri.parse(url)) }
                                        catch (_: ActivityNotFoundException) { browserError = true }
                                    }
                                }) { Text("Open provider sign-in") }
                            }
                            if (browserError) Text("Could not open the provider browser.")
                            if (attempt.authorizationUrl != null && !attempt.codeSubmitted) {
                                OutlinedTextField(code, { code = it }, label = { Text("Full code#state") }, singleLine = true,
                                    visualTransformation = androidx.compose.ui.text.input.PasswordVisualTransformation(), enabled = !state.busy)
                                Button(onClick = { val submitted = code; code = ""; store.submitCode(submitted) }, enabled = !state.busy && code.isNotEmpty()) { Text("Submit sign-in code") }
                            }
                        }
                        OutlinedButton(onClick = { code = ""; store.cancelLogin() }, enabled = !state.busy && state.loginReconciled && !state.attemptMismatch && attempt?.pending == true && attempt.valid(System.currentTimeMillis())) { Text("Cancel sign-in") }
                        if (attempt != null && !attempt.pending) OutlinedButton(onClick = store::confirmLoginRestart, enabled = !state.busy && state.loginReconciled && !state.attemptMismatch) { Text("Review and allow a new sign-in") }
                    }
                } else if (selection.selected != null) Text("Provider setup for self-hosted Agents is not available here.")
            } else Text("Only a current workspace administrator can create Agents or manage provider sign-in.")
            Text("Closing this sheet stops local polling. It does not cancel server sign-in.")
            TextButton(onClick = { code = ""; onDismiss() }) { Text("Close") }
            Spacer(Modifier.height(16.dp))
        }
    }
}

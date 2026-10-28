package ai.nuphos.android.ui.chat

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import ai.nuphos.android.model.ChatPart
import ai.nuphos.android.model.Plan
import ai.nuphos.android.session.ChatSession
import ai.nuphos.android.ui.components.StatusBadge
import ai.nuphos.android.ui.plans.PlanSteps
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** The plan id a plan-proposing tool returned, matching iOS ToolCallRow.planId. */
internal val ChatPart.Tool.planId: String?
    get() {
        if (toolName !in setOf("plan_create", "database_change_propose")) return null
        val out = output ?: return null
        return listOf(out["planId"], out["id"], out["plan"]?.get("planId"), out["plan"]?.get("id"))
            .firstNotNullOfOrNull { it?.stringValue ?: it?.numberValue?.toLong()?.toString() }
    }

/**
 * iOS PlanCard: title, status, overview, steps and cost/risk facts, with
 * Approve / Request changes / Reject only while the plan is still proposed and
 * the conversation is writable. Polls while the plan is active.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun InlinePlanCard(planId: String, session: ChatSession) {
    var plan by remember(planId) { mutableStateOf<Plan?>(null) }
    var error by remember(planId) { mutableStateOf<String?>(null) }
    var busy by remember(planId) { mutableStateOf(false) }
    var revise by remember(planId) { mutableStateOf(false) }
    var reason by remember(planId) { mutableStateOf("") }
    val scope = rememberCoroutineScope()
    LaunchedEffect(planId) {
        while (true) {
            try { val p = session.plan(planId); plan = p; error = null; if (p.status !in ACTIVE) break }
            catch (e: Exception) { if (plan == null) error = e.message ?: "Couldn't load the plan." ; if (plan == null) break }
            delay(1500)
        }
    }
    fun run(op: suspend () -> Plan) {
        if (busy) return
        busy = true
        scope.launch {
            try { plan = op(); error = null } catch (e: Exception) { error = e.message ?: "Action failed. Try again." }
            finally { busy = false }
        }
    }
    Surface(
        modifier = Modifier.fillMaxWidth().padding(top = 8.dp).testTag("inline-plan:$planId"),
        shape = MaterialTheme.shapes.medium,
        color = MaterialTheme.colorScheme.surface,
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant),
    ) {
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            val p = plan
            if (p == null) {
                if (error != null) Text(error.orEmpty(), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
                else Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
                    Text("Loading plan…", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                return@Column
            }
            Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(p.number?.let { "Plan #$it" } ?: "Plan #${p.id}", style = MaterialTheme.typography.labelSmall,
                        fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(p.title, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold)
                }
                StatusBadge(p.status)
            }
            if (p.overview.isNotEmpty()) SelectionContainer { Text(p.overview, style = MaterialTheme.typography.bodyMedium) }
            if (p.steps.isNotEmpty()) PlanSteps(p.steps)
            val facts = buildList {
                p.costSummary?.takeIf { it.isNotEmpty() }?.let { add("Cost" to it) }
                p.riskWorstCase?.takeIf { it.isNotEmpty() }?.let { add("Worst case" to it) }
                if (p.riskMitigations.isNotEmpty()) add("Mitigations" to p.riskMitigations.joinToString(" · "))
                p.approvalProgress?.let { ap ->
                    val remaining = maxOf(0, ap.minimumOtherApprovals - ap.otherApprovals)
                    if (!ap.satisfied && p.status == "proposed" && remaining > 0) add("Approvals" to "waiting for $remaining more")
                }
            }
            facts.forEach { (label, value) ->
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("$label:", style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(value, style = MaterialTheme.typography.labelSmall)
                }
            }
            if (p.status == "proposed" && !session.readOnly) {
                val enabled = !busy && !session.isStreaming
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(enabled = enabled, onClick = { run { session.approvePlan(p.id) } }) { Text("Approve") }
                    OutlinedButton(enabled = enabled, onClick = { revise = true }) { Text("Request changes") }
                    OutlinedButton(enabled = enabled, onClick = { run { session.rejectPlan(p.id) } },
                        colors = ButtonDefaults.outlinedButtonColors(contentColor = MaterialTheme.colorScheme.error)) { Text("Reject") }
                }
            }
            if (error != null) Text(error.orEmpty(), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
        }
    }
    if (revise) AlertDialog(onDismissRequest = { revise = false }, title = { Text("Request changes") },
        text = { OutlinedTextField(reason, { reason = it }, label = { Text("What should change?") }) },
        confirmButton = { TextButton(enabled = reason.isNotBlank(), onClick = { session.requestPlanChanges(reason); reason = ""; revise = false }) { Text("Send") } },
        dismissButton = { TextButton(onClick = { revise = false }) { Text("Cancel") } })
}

private val ACTIVE = setOf("proposed", "approved", "executing")

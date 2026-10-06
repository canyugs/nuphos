package ai.nuphos.android.session

import ai.nuphos.android.data.JsonValue
import ai.nuphos.android.model.AgentConversation

object HistoryStatus {
    fun sequence(value: JsonValue?): Long? = value?.numberValue?.takeIf {
        it.isFinite() && it >= 0 && it <= 9007199254740991.0 && it % 1.0 == 0.0
    }?.toLong()
    fun unread(row: AgentConversation) = row.isOwner == true && row.unread?.boolValue == true
    data class Observation(val runtime: RuntimeObservation, val activeRun: Boolean) {
        fun accepts(next: Observation) = runtime.accepts(next.runtime)
        fun label(now: Double): String? {
            if (!runtime.fresh(now) || runtime.snapshot["schemaVersion"]?.numberValue != 2.0) return null
            val state = runtime.snapshot["state"]?.stringValue
            if (state !in setOf("active", "idle", "dormant", "interrupted")) return null
            return when {
                runtime.phase == "resume_disconnected" -> "Paused"
                runtime.phase == "background_tools" -> "Background tools"
                state == "active" || activeRun -> "Running"
                else -> null
            }
        }
    }
    fun observe(row: AgentConversation, at: Double) = Observation(
        RuntimeObservation(row.runtimeState ?: JsonValue.obj(), at), row.activeRun?.get("streamId")?.stringValue?.isNotBlank() == true)
    fun mergeRead(row: AgentConversation, requested: Long, activity: Long, read: Long): AgentConversation {
        if (row.isOwner != true) return row
        val knownActivity = sequence(row.activitySeq) ?: return row
        val mergedActivity = maxOf(knownActivity, activity)
        val mergedRead = maxOf(sequence(row.readSeq) ?: 0, minOf(requested, read, activity))
        return row.copy(activitySeq = JsonValue.Number(mergedActivity.toDouble()), readSeq = JsonValue.Number(mergedRead.toDouble()), unread = JsonValue.Bool(mergedActivity > mergedRead))
    }
}

/** A displayed transcript permits at most one retry, within its visible lifetime. */
class ConversationReads {
    data class Target(val account: String, val teamId: String, val sessionId: String)
    data class Ticket(val target: Target, val generation: Long, val seq: Long, val visibility: Long)
    private var target: Target? = null
    private var visibility = 0L
    private var pending: Ticket? = null
    private var marker: Pair<Long, Long>? = null
    private var attempts = 0
    private var acknowledged = false
    fun visible(value: Target) { if (target != value) { hidden(); target = value } }
    fun hidden() { visibility++; target = null; pending = null; marker = null; attempts = 0; acknowledged = false }
    fun begin(value: Target, generation: Long, seq: Long?): Ticket? {
        if (target != value || seq == null || seq < 0 || seq > 9007199254740991L) return null
        if (marker != generation to seq) { marker = generation to seq; attempts = 0; acknowledged = false; pending = null }
        if (pending != null || acknowledged || attempts >= 2) return null
        return Ticket(value, generation, seq, visibility).also { pending = it; attempts++ }
    }
    fun accepts(ticket: Ticket, current: Target, generation: Long, allowed: Boolean) =
        allowed && target == current && ticket.target == current && ticket.visibility == visibility && ticket.generation == generation && pending == ticket
    fun failed(ticket: Ticket) { if (pending == ticket) pending = null }
    fun completed(ticket: Ticket) { if (pending == ticket) { pending = null; acknowledged = true } }
}

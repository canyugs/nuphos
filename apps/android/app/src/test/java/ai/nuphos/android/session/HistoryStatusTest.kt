package ai.nuphos.android.session

import ai.nuphos.android.data.Http
import ai.nuphos.android.data.JsonValue
import ai.nuphos.android.model.AgentConversation
import org.junit.Assert.*
import org.junit.Test

class HistoryStatusTest {
    private fun row(state: String = "active", phase: String = "working", epoch: String = "a", revision: Int = 2) =
        Http.json.decodeFromString(AgentConversation.serializer(), """{"sessionId":"s","isOwner":true,"activitySeq":4,"readSeq":1,"unread":true,"activeRun":{"streamId":"run"},"runtimeState":{"schemaVersion":2,"state":"$state","phase":"$phase","epoch":"$epoch","revision":$revision}}""")
    @Test fun decodeAndKnownStatusesExpireWithoutInventingUnknown() {
        val row = row()
        assertEquals(4L, HistoryStatus.sequence(row.activitySeq))
        assertEquals("Running", HistoryStatus.observe(row, 10.0).label(21.999))
        assertNull(HistoryStatus.observe(row, 10.0).label(22.0))
        assertEquals("Paused", HistoryStatus.observe(row(phase = "resume_disconnected"), 10.0).label(11.0))
        assertEquals("Background tools", HistoryStatus.observe(row("idle", "background_tools"), 10.0).label(11.0))
        assertNull(HistoryStatus.observe(row("unknown"), 10.0).label(11.0))
        assertFalse(HistoryStatus.unread(row.copy(isOwner = false)))
        assertNull(HistoryStatus.sequence(JsonValue.Number(1.5)))
        assertNull(HistoryStatus.sequence(JsonValue.Number(9007199254740992.0)))
    }
    @Test fun runtimeOrderingRetainsEpochAndRevisionRules() {
        val current = HistoryStatus.observe(row(), 10.0)
        assertFalse(current.accepts(HistoryStatus.observe(row(revision = 1), 11.0)))
        assertFalse(current.accepts(HistoryStatus.observe(row(epoch = "old"), 9.0)))
        assertTrue(current.accepts(HistoryStatus.observe(row(epoch = "new", revision = 1), 11.0)))
    }
    @Test fun oldAcknowledgementDoesNotEraseNewerActivity() {
        val current = row().copy(activitySeq = JsonValue.Number(8.0))
        val merged = HistoryStatus.mergeRead(current, 4, 4, 4)
        assertTrue(HistoryStatus.unread(merged))
        assertEquals(4L, HistoryStatus.sequence(merged.readSeq))
        assertEquals(8L, HistoryStatus.sequence(merged.activitySeq))
    }
    @Test fun displayedCoordinatorRejectsHiddenLateAndFutureAndBoundsRetries() {
        val reads = ConversationReads()
        val target = ConversationReads.Target("account", "team", "session")
        reads.visible(target)
        assertNull(reads.begin(target, 1, null))
        val first = reads.begin(target, 1, 4)!!
        assertNull(reads.begin(target, 1, 4))
        reads.failed(first)
        val retry = reads.begin(target, 1, 4)!!
        reads.failed(retry)
        assertNull(reads.begin(target, 1, 4))
        val next = reads.begin(target, 2, 5)!!
        reads.hidden()
        assertFalse(reads.accepts(next, target, 2, true))
        reads.visible(target.copy(teamId = "other"))
        assertNull(reads.begin(target, 2, 5))
    }
}

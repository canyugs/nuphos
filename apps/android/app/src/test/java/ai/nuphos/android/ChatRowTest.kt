package ai.nuphos.android

import ai.nuphos.android.model.ChatMessage
import ai.nuphos.android.model.ChatPart
import ai.nuphos.android.model.ChatRow
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ChatRowTest {
    private fun tool(id: String) = ChatPart.Tool(
        toolCallId = id,
        toolName = "terminal",
        isDynamic = false,
        state = ChatPart.Tool.State.OutputAvailable,
    )

    private fun message() = ChatMessage(
        id = "shared-history",
        parts = listOf(
            ChatPart.Reasoning(text = "First inspection"),
            tool("first"),
            ChatPart.Text(text = "Intermediate result"),
            ChatPart.Reasoning(text = "Second inspection"),
            tool("second"),
            ChatPart.Text(text = "Final result"),
        ),
    )

    @Test
    fun separateWorkGroupsHaveUniqueStableKeysAndPreserveHistory() {
        val rows = ChatRow.rows(listOf(message()))
        assertEquals("LazyColumn keys must be unique", rows.size, rows.map { it.id }.distinct().size)
        val groups = rows.filterIsInstance<ChatRow.Work>()
        assertEquals(2, groups.size)
        assertEquals(listOf("first", "second"), groups.flatMap { group ->
            group.rows.filterIsInstance<ChatRow.Tool>().map { it.part.toolCallId }
        })
        assertEquals(listOf("Intermediate result", "Final result"), rows.filterIsInstance<ChatRow.AssistantText>().map { it.text })
        val streamedTextUpdate = message().copy(parts = message().parts.dropLast(1) + ChatPart.Text(text = "Final result updated"))
        assertEquals(groups.map { it.id }, ChatRow.rows(listOf(streamedTextUpdate)).filterIsInstance<ChatRow.Work>().map { it.id })
    }

    @Test
    fun liveWorkRemainsVisibleUntilTheTurnFinishes() {
        val rows = ChatRow.rows(listOf(message()), isStreaming = true)
        assertTrue(rows.none { it is ChatRow.Work })
        assertEquals(2, rows.filterIsInstance<ChatRow.Tool>().size)
        assertTrue(rows.any { it is ChatRow.Activity })
    }
}

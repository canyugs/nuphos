package ai.nuphos.android

import ai.nuphos.android.data.NuphosWeb
import ai.nuphos.android.model.HistoryTime
import ai.nuphos.android.model.PlanLink
import ai.nuphos.android.ui.components.MarkdownStreamUpdate
import ai.nuphos.android.ui.components.markdownStreamUpdate
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

class NuphosLogicTest {
    @Test
    fun loginUrlIncludesMobileState() {
        val url = NuphosWeb.loginUrl()
        assertTrue(url.startsWith("https://nuphos.ai/login"))
        assertTrue(url.contains("state="))
    }

    @Test
    fun parseCallbackToken() {
        val result = NuphosWeb.parseCallback("nuphos://google-callback?token=abc123")
        assertEquals(NuphosWeb.CallbackResult.Token("abc123"), result)
    }

    @Test
    fun parseCallbackError() {
        val result = NuphosWeb.parseCallback("nuphos://google-callback?error=denied")
        assertEquals(NuphosWeb.CallbackResult.Failure("denied"), result)
    }

    @Test
    fun parseCallbackIgnoresOtherSchemes() {
        assertNull(NuphosWeb.parseCallback("https://nuphos.ai/login"))
    }

    @Test
    fun historyTimeNow() {
        val now = Instant.parse("2026-08-26T12:00:00Z")
        assertEquals("now", HistoryTime.format(now, now))
    }

    @Test
    fun historyTimeMinutes() {
        val now = Instant.parse("2026-08-26T12:00:00Z")
        val then = now.minusSeconds(5 * 60)
        assertEquals("5 min", HistoryTime.format(then, now))
    }

    @Test
    fun planLinkParsesTeamAndPlan() {
        val target = PlanLink.target("https://nuphos.ai/teams/teamA/plans/planB")
        assertEquals("teamA", target?.teamId)
        assertEquals("planB", target?.planId)
    }

    @Test
    fun markdownStreamAppendsOnlyTheDelta() {
        assertEquals(MarkdownStreamUpdate.None, markdownStreamUpdate("Hello", "Hello"))
        assertEquals(MarkdownStreamUpdate.Append(" world"), markdownStreamUpdate("Hello", "Hello world"))
        assertEquals(MarkdownStreamUpdate.Restart, markdownStreamUpdate("Hello world", "Hi"))
    }
}

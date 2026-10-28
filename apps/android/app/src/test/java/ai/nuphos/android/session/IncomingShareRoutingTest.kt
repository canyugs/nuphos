package ai.nuphos.android.session

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test

@OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
class IncomingShareRoutingTest {
    private val key = ComposerDrafts.Key("account", "current-workspace", ComposerDrafts.Destination.NewChat)
    private val share = IncomingShares.Pending(7, "account", text = "Shared note", loading = false)

    private val noRelease: (Long, ComposerDrafts.Key) -> Unit = { _, _ -> fail("No release") }

    @Test fun readyShareChoosesOnlyTheCurrentWorkspaceNewDraftBeforeNavigation() = runTest {
        val calls = mutableListOf<String>()
        assertTrue(openSharedNewDraft(share, key, { true }, { id, destination ->
            assertEquals(7L, id); assertEquals(key, destination); calls += "choose"; true
        }, { calls += "navigate" }, noRelease))
        assertEquals(listOf("choose", "navigate"), calls)
    }

    @Test fun loadingErrorWrongAccountAndExistingConversationNeverRoute() = runTest {
        val requests = listOf(share.copy(loading = true), share.copy(error = "Invalid attachment"),
            share.copy(accountId = "other-account"))
        for (request in requests) assertFalse(openSharedNewDraft(request, key, { true },
            { _, _ -> fail("No draft choice"); false }, { fail("No navigation") }, noRelease))
        assertFalse(openSharedNewDraft(share, key.copy(destination = ComposerDrafts.Destination.Chat("existing")), { true },
            { _, _ -> fail("No existing conversation routing"); false }, { fail("No navigation") }, noRelease))
    }

    @Test fun restartedRouteReopensTheSameChoiceWithoutChoosingAgain() = runTest {
        var navigated = 0
        assertTrue(openSharedNewDraft(share.copy(destination = key), key, { true },
            { _, _ -> fail("Already chosen"); false }, { navigated++ }, noRelease))
        assertEquals(1, navigated)
    }

    @Test fun choiceForAnotherWorkspaceIsReleasedNotOpened() = runTest {
        val stale = key.copy(teamId = "previous-workspace")
        var released: ComposerDrafts.Key? = null
        assertFalse(openSharedNewDraft(share.copy(destination = stale), key, { true },
            { _, _ -> fail("Release first"); false }, { fail("No navigation") }, { id, destination ->
                assertEquals(share.id, id); released = destination }))
        assertEquals(stale, released)
    }

    @Test fun staleOwnerBeforeChoiceMakesNoMutation() = runTest {
        assertFalse(openSharedNewDraft(share, key, { false }, { _, _ -> fail("Stale source"); false }, {}, noRelease))
    }

    @Test fun accountOrWorkspaceChangeDuringChoiceNeverNavigates() = runTest {
        for (change in listOf("account", "workspace", "workspace ABA", "consent", "request")) {
            var current = true
            val held = CompletableDeferred<Unit>()
            val task = async { openSharedNewDraft(share, key, { current }, { _, _ -> held.await(); true },
                { fail("Must not navigate after $change changed") }, noRelease) }
            runCurrent(); current = false; held.complete(Unit)
            assertFalse(task.await())
        }
    }

    @Test fun failedNavigationPropagatesAndKeepsTheShare() = runTest {
        try {
            openSharedNewDraft(share, key, { true }, { _, _ -> true },
                { throw IllegalStateException("No navigation host") }, noRelease)
            fail("Expected navigation failure")
        } catch (_: IllegalStateException) { }
        assertEquals("Shared note", share.text)
    }

    @Test fun cancellationDuringChoiceNeitherNavigatesNorCleansUp() = runTest {
        val held = CompletableDeferred<Unit>()
        val task = async { openSharedNewDraft(share, key, { true }, { _, _ -> held.await(); true },
            { fail("Cancelled route must not navigate") }, noRelease) }
        runCurrent(); task.cancel(); task.join()
        assertTrue(task.isCancelled)
    }

    @Test fun declinedChoiceDoesNotNavigateOrDropContent() = runTest {
        assertFalse(openSharedNewDraft(share, key, { true }, { _, _ -> false }, { fail("No navigation") }, noRelease))
        assertEquals("Shared note", share.text)
    }

    @Test fun releaseOrderedAfterQueuedChoiceKeepsShareRoutable() = runTest {
        val dispatcher = kotlinx.coroutines.test.StandardTestDispatcher(testScheduler)
        val mailbox = IncomingShares(ioDispatcher = dispatcher, uiDispatcher = dispatcher)
        try {
            mailbox.bindAccount("account")
            val id = mailbox.begin("account")!!
            mailbox.loaded(id, "Keep my note", emptyList())
            val choosing = async(kotlinx.coroutines.test.UnconfinedTestDispatcher(testScheduler)) { mailbox.choose(id, key) }
            mailbox.releaseDestination(id, key)
            choosing.await(); mailbox.awaitIdle()
            assertEquals("Keep my note", mailbox.state.value?.text)
            assertNull(mailbox.state.value?.destination)
            assertNull(mailbox.state.value?.error)
            assertFalse(mailbox.consumed(id, key))
            // A restarted route (for example after the workspace finishes loading) can still open the draft.
            assertTrue(mailbox.choose(id, key))
            assertEquals(key, mailbox.state.value?.destination)
        } finally { mailbox.close() }
    }

    @Test fun oldCleanupCannotInvalidateADifferentDestinationOrNewShare() = runTest {
        val dispatcher = kotlinx.coroutines.test.StandardTestDispatcher(testScheduler)
        val mailbox = IncomingShares(ioDispatcher = dispatcher, uiDispatcher = dispatcher)
        try {
            mailbox.bindAccount("account")
            val id = mailbox.begin("account")!!
            mailbox.loaded(id, "Keep my note", emptyList())
            val other = key.copy(teamId = "new-current-workspace")
            mailbox.choose(id, other)
            mailbox.releaseDestination(id, key); mailbox.awaitIdle()
            assertEquals(other, mailbox.state.value?.destination)
            assertNull(mailbox.state.value?.error)
            mailbox.cancel(id); mailbox.awaitIdle()
            val next = mailbox.begin("account")!!
            mailbox.loaded(next, "Next share", emptyList()); mailbox.choose(next, key)
            mailbox.releaseDestination(id, key); mailbox.awaitIdle()
            assertEquals(next, mailbox.state.value?.id)
            assertEquals(key, mailbox.state.value?.destination)
        } finally { mailbox.close() }
    }

}

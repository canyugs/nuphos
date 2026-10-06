package ai.nuphos.android

import android.content.Context
import androidx.activity.compose.setContent
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.MutableState
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import ai.nuphos.android.data.*
import ai.nuphos.android.model.*
import ai.nuphos.android.session.*
import ai.nuphos.android.ui.*
import ai.nuphos.android.ui.agent.AgentPage
import ai.nuphos.android.ui.chat.ConversationScreen
import ai.nuphos.android.ui.theme.NuphosTheme
import kotlinx.coroutines.*
import okhttp3.*
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.ExternalResource
import org.junit.rules.RuleChain
import org.junit.runner.RunWith
import java.time.Instant
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** All HTTP requests are intercepted; no credentials or server are used. */
@RunWith(AndroidJUnit4::class)
class HistoryStatusFixtureDeviceTest {
    private val compose = createAndroidComposeRule<MainActivity>()
    private val requests = CopyOnWriteArrayList<Request>()
    private val originals = mutableMapOf<String, OkHttpClient>()
    private val token = "history-fixture-no-credentials"
    private lateinit var store: AgentStore
    private lateinit var auth: AuthSession
    private lateinit var app: NuphosApplication
    private var savedAccess: Any? = null
    @Volatile private var owner = true
    @Volatile private var failDetail = false
    @Volatile private var failRead = false
    @Volatile private var holdRead = false
    @Volatile private var holdDetail = false
    private val detailHeld = CountDownLatch(1)
    private val detailRelease = CountDownLatch(1)
    private val detailReturned = CountDownLatch(1)
    private val held = CountDownLatch(1)
    private val release = CountDownLatch(1)
    @Suppress("UNCHECKED_CAST") private fun state(target: Any, name: String, delegated: Boolean = true) =
        target.javaClass.getDeclaredField(name + if (delegated) "\$delegate" else "").also { it.isAccessible = true }.get(target) as MutableState<Any?>
    private fun row(seq: Long = 4) = AgentConversation("saved", "A", "History fixture", isOwner = owner,
        activitySeq = JsonValue.Number(seq.toDouble()), readSeq = JsonValue.Number(1.0), unread = JsonValue.Bool(owner),
        activeRun = JsonValue.obj("streamId" to JsonValue.Str("run")),
        runtimeState = JsonValue.parse("""{"schemaVersion":2,"state":"active","phase":"working","epoch":"a","revision":2}"""))
    private val network = object : ExternalResource() {
        override fun before() {
            app = InstrumentationRegistry.getInstrumentation().targetContext.applicationContext as NuphosApplication
            InstrumentationRegistry.getInstrumentation().runOnMainSync {
                savedAccess = state(AiAccess, "state", false).value
                AiAccess.activate(token)
            }
            val client = OkHttpClient.Builder().addInterceptor { chain ->
                val req = chain.request(); requests += req
                var code = 200
                val body = when (req.url.encodedPath) {
                    "/teams/A/favorites" -> """{"revision":1,"entries":[]}"""
                    "/agent/conversations" -> Http.json.encodeToString(AgentConversationsPage.serializer(), AgentConversationsPage(listOf(row())))
                    "/agent/conversations/saved" -> {
                        if (holdDetail) { detailHeld.countDown(); check(detailRelease.await(10, TimeUnit.SECONDS)) }
                        detailReturned.countDown()
                        if (failDetail) { code = 403; "{}" } else
                        Http.json.encodeToString(AgentConversationDetail.serializer(), AgentConversationDetail(isOwner = owner,
                            activitySeq = JsonValue.Number(4.0), agentRuntime = "nuphos", title = "History fixture",
                            messages = listOf(ChatMessage(id = "saved-message", parts = listOf(ChatPart.Text(text = "Displayed owner transcript"))))))
                    }
                    "/agent/conversations/saved/read" -> {
                        val buffer = okio.Buffer(); req.body!!.writeTo(buffer)
                        val payload = JsonValue.parse(buffer.readUtf8())!!
                        assertEquals("A", payload["teamId"]?.stringValue)
                        assertEquals(4.0, payload["seq"]?.numberValue)
                        if (holdRead) { held.countDown(); check(release.await(10, TimeUnit.SECONDS)) }
                        if (failRead) { code = 503; "{}" } else """{"activitySeq":4,"readSeq":4,"unread":false}"""
                    }
                    else -> { code = 404; "{}" }
                }
                Response.Builder().request(req).protocol(Protocol.HTTP_1_1).code(code).message("fixture")
                    .body(body.toResponseBody(Http.jsonMedia)).build()
            }.build()
            for (name in listOf("client", "chatClient")) {
                val field = Http::class.java.getDeclaredField(name).also { it.isAccessible = true }
                originals[name] = field.get(null) as OkHttpClient; field.set(null, client)
            }
        }
        override fun after() {
            release.countDown()
            detailRelease.countDown()
            InstrumentationRegistry.getInstrumentation().runOnMainSync {
                if (::store.isInitialized) store.disposeForConsent()
                state(AiAccess, "state", false).value = savedAccess
            }
            originals.forEach { (name, client) -> Http::class.java.getDeclaredField(name).also { it.isAccessible = true }.set(null, client) }
        }
    }
    @get:Rule val rules: RuleChain = RuleChain.outerRule(network).around(compose)
    private fun render() {
        compose.runOnIdle {
            AiAccess.grant(token)
            store = AgentStore(token, compose.activity)
            state(store, "selectedTeam").value = Team("A", "Fixture A")
            state(store, "phase").value = AgentStore.Phase.Loaded
            auth = AuthSession(app, app.tokenStore)
            AuthSession::class.java.getDeclaredField("token").also { it.isAccessible = true }.set(auth, token)
            compose.activity.setContent {
                NuphosTheme { CompositionLocalProvider(LocalAgentStore provides store, LocalAuthSession provides auth) {
                    val nav = rememberNavController()
                    NavHost(nav, startDestination = "history") {
                        composable("history") { AgentPage(false, {}, nav) }
                        composable("conversation/{sessionId}") { back ->
                            ConversationScreen(back.arguments!!.getString("sessionId")!!, false, { nav.popBackStack() }, nav)
                        }
                    }
                } }
            }
        }
        val work = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
        compose.runOnIdle { work.launch { store.reload() } }
        waitText("History fixture")
        work.cancel()
    }
    private fun waitText(text: String) { compose.waitUntil(5_000) { compose.onAllNodesWithText(text).fetchSemanticsNodes().isNotEmpty() } }
    private fun readCount() = requests.count { it.url.encodedPath.endsWith("/read") }
    @Test fun listIndicatorExpiresAndOnlyDisplayedOwnerAcknowledges() {
        render()
        compose.onNodeWithText("Running").assertIsDisplayed()
        assertEquals(0, readCount())
        android.os.SystemClock.sleep(12_100)
        compose.waitUntil(15_000) { compose.onAllNodesWithText("Running").fetchSemanticsNodes().isEmpty() }
        compose.onNodeWithText("Unread").assertIsDisplayed()
        compose.onNodeWithText("History fixture").performClick()
        waitText("Displayed owner transcript")
        compose.waitUntil(5_000) { readCount() == 1 }
        compose.waitUntil(5_000) { !HistoryStatus.unread(store.conversations.single()) }
    }
    @Test fun sharedTranscriptNeverAcknowledges() {
        owner = false; render()
        compose.onNodeWithText("History fixture").performClick(); waitText("Displayed owner transcript")
        compose.mainClock.advanceTimeBy(2_000); compose.waitForIdle()
        assertEquals(0, readCount())
    }
    @Test fun failedTranscriptNeverAcknowledges() {
        failDetail = true; render()
        compose.onNodeWithText("History fixture").performClick()
        compose.waitUntil(5_000) { requests.any { it.url.encodedPath == "/agent/conversations/saved" } }
        compose.mainClock.advanceTimeBy(2_000); compose.waitForIdle()
        assertEquals(0, readCount())
        assertTrue(HistoryStatus.unread(store.conversations.single()))
    }
    @Test fun failedReadRetriesOnceAndRetainsUnread() {
        failRead = true; render()
        compose.onNodeWithText("History fixture").performClick(); waitText("Displayed owner transcript")
        compose.waitUntil(5_000) { readCount() == 2 }
        compose.mainClock.advanceTimeBy(6_000); compose.waitForIdle()
        assertEquals(2, readCount())
        assertTrue(HistoryStatus.unread(store.conversations.single()))
    }
    @Test fun newerListActivitySurvivesOlderAcknowledgement() {
        holdRead = true; render()
        compose.onNodeWithText("History fixture").performClick(); waitText("Displayed owner transcript")
        assertTrue(held.await(5, TimeUnit.SECONDS))
        compose.runOnIdle { state(store, "conversations").value = listOf(row(8)) }
        release.countDown()
        compose.waitUntil(5_000) { HistoryStatus.sequence(store.conversations.single().readSeq) == 4L }
        assertTrue(HistoryStatus.unread(store.conversations.single()))
    }
    @Test fun backgroundTranscriptDoesNotAcknowledgeUntilResumed() {
        holdDetail = true; render()
        compose.onNodeWithText("History fixture").performClick()
        compose.waitUntil(5_000) { detailHeld.count == 0L }
        compose.activityRule.scenario.moveToState(androidx.lifecycle.Lifecycle.State.CREATED)
        detailRelease.countDown()
        assertTrue(detailReturned.await(5, TimeUnit.SECONDS))
        android.os.SystemClock.sleep(500)
        assertEquals(0, readCount())
        compose.activityRule.scenario.moveToState(androidx.lifecycle.Lifecycle.State.RESUMED)
        waitText("Displayed owner transcript")
        compose.waitUntil(5_000) { readCount() == 1 }
    }
    @Test fun navigationDiscardsLateAcknowledgement() {
        holdRead = true; render()
        compose.onNodeWithText("History fixture").performClick(); waitText("Displayed owner transcript")
        assertTrue(held.await(5, TimeUnit.SECONDS))
        compose.onNodeWithContentDescription("Back").performClick()
        release.countDown(); compose.waitForIdle()
        assertTrue(HistoryStatus.unread(store.conversations.single()))
    }
}

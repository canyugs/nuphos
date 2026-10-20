package ai.nuphos.android

import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.*
import androidx.compose.foundation.layout.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import android.content.Context
import android.content.ContextWrapper
import androidx.compose.runtime.MutableState
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import ai.nuphos.android.data.Http
import ai.nuphos.android.data.JsonValue
import ai.nuphos.android.model.CredentialSelection
import ai.nuphos.android.model.Team
import ai.nuphos.android.session.AgentStore
import ai.nuphos.android.session.AiAccess
import kotlinx.coroutines.*
import okhttp3.*
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.*
import org.junit.Before
import org.junit.After
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** No Activity, real login, integration mutation, or production preference file. */
@RunWith(AndroidJUnit4::class)
class CredentialDefaultsVisualFixtureDeviceTest {
    @get:org.junit.Rule val compose = androidx.compose.ui.test.junit4.createComposeRule()
    private var picker by androidx.compose.runtime.mutableStateOf(false)
    private var sceneTitle by androidx.compose.runtime.mutableStateOf("Synthetic new-conversation fixture")
    private val token = "synthetic-credential-defaults"
    private val a = Team("aaaaaaaaaaaaaaaaaaaaaaaa", "Fixture A")
    private val b = Team("bbbbbbbbbbbbbbbbbbbbbbbb", "Fixture B")
    private val requests = CopyOnWriteArrayList<Request>()
    private lateinit var context: Context
    private lateinit var store: AgentStore
    private lateinit var original: OkHttpClient
    private var savedAccess: Any? = null
    private var savedOnRevoked: () -> Unit = {}
    @Volatile private var status = 200
    @Volatile private var options = """{"options":{"awsRoles":[{"roleId":"cloud","accountAlias":"Fixture cloud"}],"devices":[{"deviceId":"online","label":"Fixture online computer","platform":"darwin","available":true},{"deviceId":"offline","label":"Fixture offline computer","available":false}],"resendIntegrations":[{"integrationId":"mail","label":"Fixture Resend"}]}}"""
    private var entered: CountDownLatch? = null
    private var release: CountDownLatch? = null
    @Suppress("UNCHECKED_CAST") private fun access() = AiAccess::class.java.getDeclaredField("state")
        .also { it.isAccessible = true }.get(AiAccess) as MutableState<Any?>

    @Before fun before() {
        val target = InstrumentationRegistry.getInstrumentation().targetContext
        org.junit.Assume.assumeTrue("Requires a separate fixture installation", target.packageName == "ai.nuphos.android.credentialfixture")
        context = object : ContextWrapper(target) {
            override fun getSharedPreferences(name: String, mode: Int) = super.getSharedPreferences("credential-defaults-visual-fixture", mode)
        }
        context.getSharedPreferences("ignored", 0).edit().clear()
            .putString("nuphos.credentialSelection.${a.id}", """{"ids":{"resendIntegrationIds":["mail"],"awsRoleIds":["old"]}}""").commit()
        val field = Http::class.java.getDeclaredField("client").also { it.isAccessible = true }
        original = field.get(null) as OkHttpClient
        field.set(null, OkHttpClient.Builder().addInterceptor { chain ->
            val request = chain.request(); requests += request
            val catalog = request.url.encodedPath == "/agent/credential-options"
            val text = if (catalog) options else """{"conversations":[],"hasMore":false}"""
            val code = if (catalog) status else 200
            if (catalog) {
                entered?.countDown()
                check(release?.await(10, TimeUnit.SECONDS) != false)
            }
            Response.Builder().request(request).protocol(Protocol.HTTP_1_1).code(code).message("fixture")
                .body(text.toResponseBody(Http.jsonMedia)).build()
        }.build())
        InstrumentationRegistry.getInstrumentation().runOnMainSync {
            savedAccess = access().value
            savedOnRevoked = AiAccess.onRevoked
            AiAccess.onRevoked = {}
            AiAccess.activate(token); AiAccess.grant(token)
            store = AgentStore(token, context)
            store.acceptMemberships(listOf(a, b), a.id)
        }
    }

    @After fun after() {
        if (!::store.isInitialized) return
        release?.countDown()
        InstrumentationRegistry.getInstrumentation().runOnMainSync {
            store.disposeForConsent()
            access().value = savedAccess
            AiAccess.onRevoked = savedOnRevoked
        }
        Http::class.java.getDeclaredField("client").also { it.isAccessible = true }.set(null, original)
        context.getSharedPreferences("ignored", 0).edit().clear().commit()
    }

    private fun render() {
        compose.setContent {
            ai.nuphos.android.ui.theme.NuphosTheme(darkTheme = false) {
                androidx.compose.runtime.CompositionLocalProvider(ai.nuphos.android.ui.LocalAgentStore provides store) {
                    androidx.compose.material3.Surface(Modifier.fillMaxSize()) {
                        Column(Modifier.fillMaxSize().systemBarsPadding().padding(16.dp)) {
                            androidx.compose.material3.Text(sceneTitle)
                            Spacer(Modifier.weight(1f))
                            ai.nuphos.android.ui.chat.ChatComposer(
                                isStreaming = false, canSubmit = store.credentialsReady,
                                onSend = { error("Fixture must never submit a message") },
                                showControls = true,
                            )
                        }
                    }
                    if (picker) ai.nuphos.android.ui.chat.CredentialPickerSheet(
                        store.credentialSelection, store::updateCredentialSelection, { picker = false },
                    )
                }
            }
        }
        compose.onNodeWithContentDescription("Ask Nuphos anything").performTextInput("Review fixture prompt")
    }

    private fun shot(name: String) {
        if (picker) {
            compose.runOnIdle { picker = false }
            compose.waitForIdle(); Thread.sleep(400)
            compose.runOnIdle { picker = true }
        }
        compose.waitForIdle()
        // Wait for the native sheet animation to settle; no global animation/theme settings.
        Thread.sleep(700)
        val bitmap = InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot()
        checkNotNull(bitmap)
        try {
            java.io.File(context.filesDir, "credential607-$name.png").outputStream().use {
                bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it)
            }
        } finally { bitmap.recycle() }
    }

    @Test fun initialLoadingAndFailureReadiness() = runBlocking {
        entered = CountDownLatch(1); release = CountDownLatch(1)
        status = 500
        val pending = launch(Dispatchers.Main) { store.loadCredentialOptions() }
        assertTrue(withContext(Dispatchers.IO) { entered!!.await(5, TimeUnit.SECONDS) })
        render()
        compose.onNodeWithContentDescription("Send").assertIsNotEnabled()
        shot("01-initial-loading-send-disabled")
        release!!.countDown(); pending.join()
        compose.onNodeWithContentDescription("Send").assertIsEnabled()
        shot("02-failed-catalog-send-ready")
        compose.runOnIdle { picker = true }
        compose.onNodeWithText(store.credentialCatalogError!!).assertIsDisplayed()
        compose.runOnIdle { assertNotNull(store.credentialCatalogError) }
        shot("03-failed-catalog-picker-error")
        assertTrue(requests.all { it.method == "GET" })
    }

    @Test fun defaultsAndDeselectSurviveRefresh() = runBlocking {
        withContext(Dispatchers.Main) { store.loadCredentialOptions() }
        withContext(Dispatchers.Main) { store.updateCredentialSelection(CredentialSelection()) }
        render()
        compose.runOnIdle { sceneTitle = "Synthetic reconstruction: previous empty defaults"; picker = true }
        compose.onNodeWithText("Fixture online computer").assertIsOff()
        compose.onNodeWithText("Fixture Resend").performScrollTo().assertIsDisplayed()
        shot("00-prior-empty-defaults-reconstructed")
        withContext(Dispatchers.Main) {
            store.select(b); store.select(a)
            store.loadCredentialOptions()
        }
        compose.runOnIdle { sceneTitle = "Synthetic fixture: current defaults" }
        compose.onNodeWithText("Fixture online computer").assertIsOn()
        compose.onNodeWithText("Fixture offline computer").assertDoesNotExist()
        compose.runOnIdle {
            assertEquals(setOf("cloud"), store.credentialSelection.ids["awsRoleIds"])
            assertTrue(store.credentialSelection.ids["resendIntegrationIds"]!!.isEmpty())
        }
        compose.onNodeWithText("Fixture Resend").assertIsDisplayed()
        compose.onNodeWithText("Fixture Resend").performScrollTo().assertIsDisplayed()
        shot("04-defaults-online-cloud-selected-resend-excluded")
        compose.onNodeWithText("Fixture online computer").performClick().assertIsOff()
        compose.onNodeWithText("Fixture cloud").performClick()
        withContext(Dispatchers.Main) { store.loadCredentialOptions(force = true) }
        compose.onNodeWithText("Fixture online computer").assertIsOff()
        compose.runOnIdle { assertTrue(store.credentialSelection.ids["awsRoleIds"]!!.isEmpty()) }
        compose.onNodeWithText("Fixture Resend").performScrollTo().assertIsDisplayed()
        shot("05-deselection-survives-refresh")
        compose.onNodeWithText("Fixture Resend").performClick()
        withContext(Dispatchers.Main) { store.loadCredentialOptions(force = true) }
        compose.runOnIdle { assertEquals(setOf("mail"), store.credentialSelection.ids["resendIntegrationIds"]) }
        compose.onNodeWithText("Fixture Resend").performScrollTo().assertIsDisplayed()
        shot("06-explicit-resend-opt-in-survives-refresh")
        assertTrue(requests.all { it.method == "GET" })
    }
}

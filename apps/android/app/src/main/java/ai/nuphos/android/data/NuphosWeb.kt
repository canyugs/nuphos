package ai.nuphos.android.data

import android.net.Uri
import java.net.URI
import java.net.URLDecoder
import java.util.Base64

/**
 * Browser leg of sign-in. `/login?state=` accepts an unsigned base64url JSON
 * blob; with `mobile: true`, `/api/google/callback` finishes with
 * `nuphos://google-callback?token=` or `?error=`.
 */
object NuphosWeb {
    const val SITE_URL = "https://nuphos.ai"
    const val CALLBACK_SCHEME = "nuphos"
    const val CALLBACK_HOST = "google-callback"

    sealed class CallbackResult {
        data class Token(val token: String) : CallbackResult()
        data class Failure(val message: String) : CallbackResult()
    }

    fun loginUrl(): String {
        val state = Base64.getUrlEncoder()
            .withoutPadding()
            .encodeToString("""{"mobile":true}""".toByteArray(Charsets.UTF_8))
        return "$SITE_URL/login?state=$state"
    }

    fun parseCallback(uri: Uri): CallbackResult? =
        parseCallback(uri.scheme, uri.host, uri.encodedQuery)

    fun parseCallback(uriString: String): CallbackResult? {
        val uri = runCatching { URI(uriString) }.getOrNull() ?: return null
        return parseCallback(uri.scheme, uri.host, uri.rawQuery)
    }

    private fun parseCallback(scheme: String?, host: String?, query: String?): CallbackResult? {
        if (scheme?.lowercase() != CALLBACK_SCHEME) return null
        if (host?.lowercase() != CALLBACK_HOST) return null
        val params = parseQuery(query)
        params["token"]?.takeIf { it.isNotEmpty() }?.let { return CallbackResult.Token(it) }
        params["error"]?.takeIf { it.isNotEmpty() }?.let { return CallbackResult.Failure(it) }
        return CallbackResult.Failure("Google did not complete this sign-in.")
    }

    private fun parseQuery(query: String?): Map<String, String> {
        if (query.isNullOrEmpty()) return emptyMap()
        return query.split("&").mapNotNull { part ->
            val idx = part.indexOf('=')
            if (idx <= 0) return@mapNotNull null
            val key = URLDecoder.decode(part.substring(0, idx), Charsets.UTF_8)
            val value = URLDecoder.decode(part.substring(idx + 1), Charsets.UTF_8)
            key to value
        }.toMap()
    }
}

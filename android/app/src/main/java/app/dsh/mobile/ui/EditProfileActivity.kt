package app.dsh.mobile.ui

import android.content.ClipboardManager
import android.content.Context
import android.os.Bundle
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import app.dsh.mobile.DshApp
import app.dsh.mobile.R
import app.dsh.mobile.core.Endpoint
import app.dsh.mobile.core.Profile
import com.google.android.material.appbar.MaterialToolbar
import com.google.android.material.button.MaterialButton
import com.google.android.material.textfield.TextInputEditText
import com.google.android.material.textfield.TextInputLayout

/**
 * 添加/编辑一个入口。校验**全部委托给 [Endpoint.parse]**（核心逻辑只有一份），
 * 这个类只负责把错误显示出来。
 */
class EditProfileActivity : AppCompatActivity() {

    private val store by lazy { (application as DshApp).profileStore }
    private var existing: Profile? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_edit_profile)

        val nameLayout = findViewById<TextInputLayout>(R.id.name_layout)
        val urlLayout = findViewById<TextInputLayout>(R.id.url_layout)
        val name = findViewById<TextInputEditText>(R.id.name)
        val url = findViewById<TextInputEditText>(R.id.url)

        existing = intent.getStringExtra(Nav.EXTRA_PROFILE_ID)?.let { id -> store.load().firstOrNull { it.id == id } }
        existing?.let {
            name.setText(it.name)
            url.setText(it.endpoint.baseUrl)
        }

        findViewById<MaterialToolbar>(R.id.toolbar).apply {
            setTitle(if (existing == null) R.string.title_add_profile else R.string.title_edit_profile)
            setNavigationOnClickListener { finish() }
        }

        // 实时校验：一边输一边给判据，别等点了保存才报错
        url.addTextChangedListener(SimpleWatcher { text ->
            val error = Endpoint.parse(text).exceptionOrNull()?.message
            urlLayout.error = if (text.isBlank()) null else error
        })

        findViewById<MaterialButton>(R.id.paste).setOnClickListener {
            val clip = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            val text = clip.primaryClip?.getItemAt(0)?.coerceToText(this)?.toString().orEmpty()
            if (text.isBlank()) {
                toast(getString(R.string.toast_clipboard_empty))
            } else {
                url.setText(text)   // 支持整行粘贴：Endpoint.parse 会自己摘出 URL 与 token
            }
        }

        findViewById<MaterialButton>(R.id.save).setOnClickListener {
            val raw = url.text?.toString().orEmpty()
            val endpoint = Endpoint.parse(raw).getOrElse { error ->
                urlLayout.error = error.message
                return@setOnClickListener
            }
            val finalName = name.text?.toString()?.ifBlank { endpoint.displayName } ?: endpoint.displayName
            val profile = existing?.copy(name = finalName, endpoint = endpoint)
                ?: Profile.create(finalName, endpoint)
            if (nameLayout.error != null) nameLayout.error = null
            store.upsert(profile)
            if (profile.endpoint.token.isNullOrBlank()) {
                toast(getString(R.string.toast_saved_no_token))
            }
            finish()
        }
    }

    private fun toast(text: String) = Toast.makeText(this, text, Toast.LENGTH_LONG).show()

    /** 一个只有一个方法的 TextWatcher —— 免得每次都写三个空实现。 */
    private class SimpleWatcher(private val onChanged: (String) -> Unit) : android.text.TextWatcher {
        override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) = Unit
        override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) = Unit
        override fun afterTextChanged(s: android.text.Editable?) = onChanged(s?.toString().orEmpty())
    }
}

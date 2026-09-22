package app.dsh.mobile.ui

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import app.dsh.mobile.R
import app.dsh.mobile.core.Profile
import com.google.android.material.card.MaterialCardView

/** 入口列表。只有展示 + 两个回调，没有任何业务判断。 */
class ProfileAdapter(
    private val onClick: (Profile) -> Unit,
    private val onLongClick: (Profile) -> Unit,
) : ListAdapter<Profile, ProfileAdapter.VH>(DIFF) {

    class VH(view: View) : RecyclerView.ViewHolder(view) {
        val card: MaterialCardView = view.findViewById(R.id.card)
        val name: TextView = view.findViewById(R.id.name)
        val url: TextView = view.findViewById(R.id.url)
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): VH =
        VH(LayoutInflater.from(parent.context).inflate(R.layout.item_profile, parent, false))

    override fun onBindViewHolder(holder: VH, position: Int) {
        val profile = getItem(position)
        holder.name.text = profile.name
        holder.url.text = holder.itemView.context.getString(
            if (profile.endpoint.token.isNullOrBlank()) R.string.profile_url_no_token else R.string.profile_url_with_token,
            profile.endpoint.baseUrl,
        )
        holder.card.setOnClickListener { onClick(profile) }
        holder.card.setOnLongClickListener { onLongClick(profile); true }
    }

    private companion object {
        val DIFF = object : DiffUtil.ItemCallback<Profile>() {
            override fun areItemsTheSame(a: Profile, b: Profile) = a.id == b.id || a.endpoint.sameAuthority(b.endpoint)
            override fun areContentsTheSame(a: Profile, b: Profile) = a == b
        }
    }
}

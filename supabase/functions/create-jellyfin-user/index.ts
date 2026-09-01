import { createClient } from 'npm:@supabase/supabase-js@2'

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  })
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })

  try {
    const { invite_code, username, password } = await req.json()

    if (!invite_code || !username || !password) {
      return json({ error: 'invite_code, username, and password are required' }, 400)
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    )

    // Normalise code — ensure it has the VIBE- prefix to match DB storage
    const raw  = (invite_code as string).toUpperCase().trim()
    const code = raw.startsWith('VIBE-') ? raw : `VIBE-${raw}`

    // Validate invite and fetch server details in one query
    const { data: invite, error: inviteErr } = await supabase
      .from('invite_codes')
      .select('id, uses_remaining, servers(server_url, admin_api_key)')
      .eq('code', code)
      .gt('uses_remaining', 0)
      .maybeSingle()

    if (inviteErr || !invite) {
      return json({ error: 'Invalid or expired invite code.' }, 400)
    }

    const server = invite.servers as { server_url: string; admin_api_key: string | null } | null
    const serverUrl   = server?.server_url?.replace(/\/$/, '')
    const adminApiKey = server?.admin_api_key

    if (!serverUrl || !adminApiKey) {
      return json({
        error: 'This server hasn\'t configured automatic account creation yet. Ask the owner to add their Jellyfin admin API key in ViBE Settings → Server.',
      }, 422)
    }

    const authHeader = `MediaBrowser Client="ViBE", Device="EdgeFunction", DeviceId="vibe-edge-fn", Version="1.0", Token="${adminApiKey}"`

    // ── 1. Create Jellyfin user ───────────────────────────────────────────────
    const createRes = await fetch(`${serverUrl}/Users/New`, {
      method: 'POST',
      headers: { 'X-Emby-Authorization': authHeader, 'Content-Type': 'application/json' },
      body: JSON.stringify({ Name: username }),
    })

    if (!createRes.ok) {
      const body = await createRes.text()
      if (createRes.status === 400 || body.toLowerCase().includes('exist')) {
        return json({ error: 'That username is already taken. Please choose a different one.' }, 409)
      }
      return json({ error: 'Failed to create Jellyfin account. Check your server URL and admin API key.' }, 502)
    }

    const newUser = await createRes.json() as { Id: string }
    const jellyfinUserId = newUser.Id

    // ── 2. Set password ───────────────────────────────────────────────────────
    const pwRes = await fetch(`${serverUrl}/Users/${jellyfinUserId}/Password`, {
      method: 'POST',
      headers: { 'X-Emby-Authorization': authHeader, 'Content-Type': 'application/json' },
      body: JSON.stringify({ NewPw: password }),
    })

    if (!pwRes.ok) {
      // Rollback: delete the account we just created
      await fetch(`${serverUrl}/Users/${jellyfinUserId}`, {
        method: 'DELETE',
        headers: { 'X-Emby-Authorization': authHeader },
      }).catch(() => {})
      return json({ error: 'Failed to set Jellyfin password.' }, 502)
    }

    // ── 3. Authenticate as new user to get their token ────────────────────────
    const authRes = await fetch(`${serverUrl}/Users/AuthenticateByName`, {
      method: 'POST',
      headers: {
        'X-Emby-Authorization': `MediaBrowser Client="ViBE", Device="EdgeFunction", DeviceId="vibe-edge-fn", Version="1.0"`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ Username: username, Pw: password }),
    })

    if (!authRes.ok) {
      return json({ error: 'Account created but sign-in failed. Contact the server owner.' }, 502)
    }

    const authData = await authRes.json() as { AccessToken: string; User: { Id: string } }

    return json({
      server_url:       serverUrl,
      jellyfin_user_id: authData.User.Id,
      jellyfin_token:   authData.AccessToken,
      invite_id:        invite.id,
    })

  } catch (err) {
    console.error('create-jellyfin-user error:', err)
    return json({ error: 'Internal server error.' }, 500)
  }
})

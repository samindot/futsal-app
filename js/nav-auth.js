import { supabase } from './supabase.js'
import { getCurrentProfile } from './api.js'
import { logout } from './auth.js'

/**
 * Keep the navigation in sync with the persisted Supabase session.
 * Auth callbacks only update UI synchronously; profile requests run separately
 * to avoid awaiting Supabase calls from inside onAuthStateChange.
 */
export function initAuthNav() {
  const greeting = document.getElementById('userGreeting')
  const loginLink = document.getElementById('loginLink')
  const logoutButton = document.getElementById('logoutButton')
  const adminLink = document.getElementById('adminLink')
  if (!greeting || !loginLink || !logoutButton) return

  let profileRequest = 0
  const render = (session) => {
    const user = session?.user || null
    if (!user) {
      profileRequest++
      greeting.textContent = ''
      greeting.classList.add('hidden')
      loginLink.classList.remove('hidden')
      logoutButton.classList.add('hidden')
      adminLink?.classList.add('hidden')
      return
    }
    const displayName = user.user_metadata?.display_name
      || user.user_metadata?.full_name
      || user.email?.split('@')[0]
      || 'Pemain'
    greeting.textContent = `Halo, ${displayName}!`
    greeting.classList.remove('hidden')
    loginLink.classList.add('hidden')
    logoutButton.classList.remove('hidden')
    adminLink?.classList.add('hidden')

    if (adminLink) {
      const requestId = ++profileRequest
      getCurrentProfile().then(profile => {
        if (requestId === profileRequest && profile?.role === 'admin') {
          adminLink.classList.remove('hidden')
        }
      }).catch(error => console.warn('Could not load account role', error))
    }
  }

  logoutButton.addEventListener('click', async () => {
    logoutButton.disabled = true
    try {
      await logout()
    } catch (error) {
      console.error('Logout failed', error)
      window.alert('Logout belum berhasil. Periksa koneksi lalu coba lagi.')
      logoutButton.disabled = false
    }
  })

  const { data: { subscription } } = supabase.auth.onAuthStateChange((_event, session) => {
    render(session)
  })
  window.addEventListener('pagehide', () => subscription.unsubscribe(), { once: true })
}

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
  const dashboardLink = document.getElementById('dashboardLink')
  const navLinks = document.querySelector('.nav-links')
  if (!greeting || !loginLink || !logoutButton) return

  let profileRequest = 0
  let notificationRequest = 0
  let notificationLink = document.getElementById('navNotificationsLink')
  if (!notificationLink && navLinks) {
    notificationLink = document.createElement('a')
    notificationLink.id = 'navNotificationsLink'
    notificationLink.className = 'nav-notification-link hidden'
    notificationLink.href = './matchmaking.html#myNotifications'
    notificationLink.setAttribute('aria-label', 'Notifikasi sparing')
    notificationLink.innerHTML = '<span aria-hidden="true">♧</span><span class="nav-notification-label">Notifikasi</span><span id="navNotificationBadge" class="nav-notification-badge hidden">0</span>'
    greeting.insertAdjacentElement('afterend', notificationLink)
  }
  const refreshNotificationCount = async (user) => {
    const requestId = ++notificationRequest
    if (!notificationLink || !user) {
      notificationLink?.classList.add('hidden')
      return
    }
    try {
      const { count, error } = await supabase.from('matchmaking_notifications')
        .select('id', { count: 'exact', head: true })
        .eq('recipient_id', user.id)
        .is('read_at', null)
      if (error) throw error
      if (requestId !== notificationRequest) return
      notificationLink.classList.remove('hidden')
      const badge = document.getElementById('navNotificationBadge')
      if (badge) {
        badge.textContent = String(count || 0)
        badge.classList.toggle('hidden', !count)
        notificationLink.setAttribute('aria-label', count ? `Notifikasi sparing, ${count} belum dibaca` : 'Notifikasi sparing, tidak ada yang belum dibaca')
      }
    } catch (error) {
      if (requestId === notificationRequest) {
        notificationLink.classList.add('hidden')
        console.warn('Could not load unread notification count', error)
      }
    }
  }
  window.addEventListener('futsalkita-notifications-updated', event => {
    if (!notificationLink) return
    const count = Number(event.detail?.unread || 0)
    const badge = document.getElementById('navNotificationBadge')
    notificationLink.classList.remove('hidden')
    if (badge) {
      badge.textContent = String(count)
      badge.classList.toggle('hidden', count === 0)
      notificationLink.setAttribute('aria-label', count ? `Notifikasi sparing, ${count} belum dibaca` : 'Notifikasi sparing, tidak ada yang belum dibaca')
    }
  })
  const render = (session) => {
    const user = session?.user || null
    if (!user) {
      profileRequest++
      greeting.textContent = ''
      greeting.classList.add('hidden')
      loginLink.classList.remove('hidden')
      logoutButton.classList.add('hidden')
      adminLink?.classList.add('hidden')
      dashboardLink?.classList.add('hidden')
      notificationRequest++
      notificationLink?.classList.add('hidden')
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
    dashboardLink?.classList.remove('hidden')
    adminLink?.classList.add('hidden')
    refreshNotificationCount(user)

    if (adminLink) {
      const requestId = ++profileRequest
      // Defer the profile lookup until the auth-state callback has fully returned.
      // Calling Supabase auth methods from inside onAuthStateChange can deadlock its lock.
      setTimeout(() => {
        getCurrentProfile().then(profile => {
          if (requestId === profileRequest && profile?.role === 'admin') {
            adminLink.classList.remove('hidden')
          }
        }).catch(error => console.warn('Could not load account role', error))
      }, 0)
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
  window.addEventListener('focus', () => {
    const user = supabase.auth.getSession().then(({data}) => refreshNotificationCount(data?.session?.user || null)).catch(error => console.warn('Could not refresh notification count', error))
  })
  window.addEventListener('pagehide', () => subscription.unsubscribe(), { once: true })
}

import { supabase } from './supabase.js'

function getRedirectTarget() {
  const params = new URLSearchParams(window.location.search)
  const next = params.get('next') || 'matchmaking.html'
  return /^(index\.html|matchmaking\.html|calendar\.html)(#booking-request)?$/.test(next)
    ? './' + next
    : './matchmaking.html'
}

function getAbsoluteRedirectTarget() {
  return new URL(getRedirectTarget(), window.location.href).href
}

function getVerificationRedirect() {
  const url = new URL('./verify.html', window.location.href)
  url.searchParams.set('next', new URLSearchParams(window.location.search).get('next') || 'matchmaking.html')
  return url.href
}

export async function login(email, password) {
  const { error } = await supabase.auth.signInWithPassword({
    email: email.trim(),
    password
  })
  if (error) throw error
  window.location.href = getRedirectTarget()
}

export async function signInWithGoogle() {
  const { error } = await supabase.auth.signInWithOAuth({
    provider: 'google',
    options: { redirectTo: getAbsoluteRedirectTarget() }
  })
  if (error) throw error
}

export async function register(email, password, displayName) {
  const { data, error } = await supabase.auth.signUp({
    email: email.trim(),
    password,
    options: {
      data: { display_name: displayName.trim() },
      emailRedirectTo: getVerificationRedirect()
    }
  })
  if (error) throw error
  if (!data.session) {
    return { confirmationRequired: true }
  }
  window.location.href = getRedirectTarget()
  return { confirmationRequired: false }
}

export async function requireAuth(next = 'calendar.html') {
  const { data, error } = await supabase.auth.getSession()
  if (error) throw error
  if (!data.session) {
    const safeNext = /^(index\.html|matchmaking\.html|calendar\.html)(#booking-request)?$/.test(next)
      ? next
      : 'matchmaking.html'
    window.location.replace('./login.html?next=' + encodeURIComponent(safeNext))
    return false
  }
  return true
}

export async function logout() {
  const { error } = await supabase.auth.signOut()
  if (error) throw error
  window.location.replace('./index.html')
}

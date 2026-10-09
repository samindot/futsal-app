import { supabase } from './supabase.js'

function getRedirectTarget() {
  const params = new URLSearchParams(window.location.search)
  const next = params.get('next') || 'matchmaking.html'
  return /^(index\.html|matchmaking\.html|calendar\.html)(#booking-request)?$/.test(next)
    ? './' + next
    : './matchmaking.html'
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
  const redirectTo = new URL(getRedirectTarget(), window.location.href).href
  const { error } = await supabase.auth.signInWithOAuth({
    provider: 'google',
    options: { redirectTo }
  })
  if (error) throw error
}

export async function register(email, password, displayName) {
  const { data, error } = await supabase.auth.signUp({
    email: email.trim(),
    password,
    options: { data: { display_name: displayName.trim() } }
  })
  if (error) throw error
  if (!data.session) {
    return { confirmationRequired: true }
  }
  window.location.href = getRedirectTarget()
  return { confirmationRequired: false }
}

export async function requireAuth() {
  const { data, error } = await supabase.auth.getSession()
  if (error) throw error
  if (!data.session) {
    window.location.replace('./login.html')
    return false
  }
  return true
}

export async function logout() {
  await supabase.auth.signOut()
  window.location.href = './index.html'
}

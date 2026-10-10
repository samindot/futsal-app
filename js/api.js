import { supabase } from './supabase.js'

async function unwrap(query) {
  const { data, error } = await query
  if (error) throw error
  return data
}

export async function getFields() {
  return unwrap(
    supabase.from('fields').select('id,name,location,hourly_rate,is_active')
      .eq('is_active', true).order('name')
  )
}

export async function getBookings(date) {
  return unwrap(
    supabase.from('bookings')
      .select('id,field_id,booking_date,start_time,duration_hours,customer_name,amount_paid,notes,status')
      .eq('booking_date', date).neq('status', 'cancelled').order('start_time')
  )
}

export async function getPublicBookings(date) {
  return unwrap(supabase.rpc('get_public_bookings', { p_date: date }))
}

export async function requestBooking(payload) {
  return unwrap(supabase.rpc('request_booking', payload))
}

export async function createBooking(payload) {
  return unwrap(supabase.rpc('create_booking', payload))
}

export async function updateBooking(id, changes) {
  return unwrap(
    supabase.from('bookings').update(changes).eq('id', id).select().single()
  )
}

export async function getCurrentProfile() {
  const { data: { user }, error: userError } = await supabase.auth.getUser()
  if (userError) throw userError
  if (!user) return null
  const { data, error } = await supabase.from('profiles')
    .select('id,display_name,phone,skill_level,role').eq('id', user.id).single()
  if (error) throw error
  return { ...data, email: user.email }
}

export async function getMatchmakingSessions() {
  return unwrap(supabase.rpc('get_matchmaking_sessions'))
}

export async function createMatchmakingSession(payload) {
  const { data: { user }, error: userError } = await supabase.auth.getUser()
  if (userError) throw userError
  if (!user) throw new Error('Silakan login terlebih dahulu.')
  return unwrap(supabase.from('matchmaking_sessions').insert({
    ...payload,
    host_id: user.id
  }).select().single())
}

export async function joinMatchmakingSession(sessionId) {
  return unwrap(supabase.rpc('join_matchmaking_session', { p_session_id: sessionId }))
}

export async function leaveMatchmakingSession(sessionId) {
  return unwrap(supabase.rpc('leave_matchmaking_session', { p_session_id: sessionId }))
}

export async function getMyParticipations() {
  const { data: { user }, error: userError } = await supabase.auth.getUser()
  if (userError) throw userError
  if (!user) return []
  return unwrap(
    supabase.from('matchmaking_players')
      .select('session_id,status').eq('player_id', user.id).eq('status', 'joined')
  )
}

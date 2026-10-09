import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js/+esm'

// Public client credentials only. Never put a service_role/secret key in frontend code.
const SUPABASE_URL = 'https://fbkgiebuozyflsbkneaf.supabase.co'
const SUPABASE_PUBLISHABLE_KEY = 'sb_publishable_BdjHH0WxMNfHHZHruo-i3A_T-iuXqh7'

export const supabase = createClient(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY)

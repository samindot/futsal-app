import { supabase } from './supabase.js'
import { initAuthNav } from './nav-auth.js'
import { getCurrentProfile } from './api.js'

const $=id=>document.getElementById(id)
const esc=value=>String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]))
initAuthNav()
async function checkAuth(){
 const {data,error}=await supabase.auth.getSession()
 if(error) throw error
 const user=data.session?.user
 if(!user){
  $('boothAuth').textContent='Belum login. Halaman ini khusus admin/petugas venue.'
  $('redeemButton').disabled=true
  return
 }
 const profile=await getCurrentProfile()
 const {data:memberships,error:membershipError}=await supabase.from('venue_members').select('id,role').eq('user_id',user.id).eq('is_active',true).limit(1)
 if(membershipError) throw membershipError
 const isVenueStaff=Boolean(memberships?.length)
 const isAdmin=profile?.role==='admin'
 if(!isAdmin&&!isVenueStaff){
  $('boothAuth').textContent='Akses ditolak. Booth hanya untuk admin atau petugas venue.'
  $('redeemButton').disabled=true
  $('redeemForm').classList.add('hidden')
  return
 }
 $('boothAuth').textContent='Login sebagai '+(user.user_metadata?.display_name||user.email||'petugas')+'. Hak akses: '+(isAdmin?'admin':memberships.map(m=>m.role).join(', '))+'. Server tetap memverifikasi keanggotaan venue saat token diproses.'
 $('redeemButton').disabled=false
 $('redeemForm').classList.remove('hidden')
}
$('redeemForm').addEventListener('submit',async e=>{
 e.preventDefault()
 const token=$('tokenInput').value.trim()
 if(!token)return
 const button=$('redeemButton');button.disabled=true;button.textContent='Memverifikasi…'
 const result=$('boothResult');result.replaceChildren()
 try{
  const {data,error}=await supabase.rpc('redeem_open_play_checkin_token',{p_token:token})
  if(error)throw error
  const row=Array.isArray(data)?data[0]:data
  if(!row)throw new Error('Server tidak mengembalikan data check-in.')
  result.className='booth-result'
  result.innerHTML='<span class="eyebrow">CHECK-IN BERHASIL</span><h2></h2><p class="player-session"></p><p class="booth-note"></p>'
  result.querySelector('h2').textContent=row.player_name||'Pemain terverifikasi'
  result.querySelector('.player-session').textContent=row.session_title||'Open Play'
  result.querySelector('.booth-note').textContent='Waktu check-in: '+new Date(row.checked_in_at||Date.now()).toLocaleString('id-ID')
  $('tokenInput').value=''
 }catch(error){
  result.className='booth-result error'
  result.innerHTML='<strong>Check-in gagal</strong><p></p><p class="booth-note">Pastikan token belum kedaluwarsa, belum digunakan, dan akun petugas merupakan anggota aktif venue sesi ini.</p>'
  result.querySelector('p').textContent=error.message||'Token tidak valid.'
 }finally{button.disabled=false;button.textContent='Verifikasi & check-in';$('tokenInput').focus()}
})
supabase.auth.onAuthStateChange(()=>checkAuth().catch(e=>{$('boothAuth').textContent=e.message}))
checkAuth().catch(e=>{$('boothAuth').textContent='Gagal memeriksa login: '+e.message})

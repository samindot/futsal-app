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
  $('startScanner').disabled=true
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
  $('scannerControls').classList.add('hidden')
  $('scannerStatus').classList.add('hidden')
  return
 }
 $('boothAuth').textContent='Login sebagai '+(user.user_metadata?.display_name||user.email||'petugas')+'. Hak akses: '+(isAdmin?'admin':memberships.map(m=>m.role).join(', '))+'. Server tetap memverifikasi keanggotaan venue saat token diproses.'
 $('redeemButton').disabled=false
 $('startScanner').disabled=false
 $('redeemForm').classList.remove('hidden')
 $('scannerControls').classList.remove('hidden')
 $('scannerStatus').classList.remove('hidden')
}
let scannerReader = null
let scannerControls = null
let scannerRunning = false
let redeeming = false

async function stopScanner(message='Kamera dimatikan.') {
 if(scannerControls) {
  try { await scannerControls.stop() } catch {}
  try { scannerControls = null } catch {}
 }
 scannerRunning = false
 $('scannerFrame').classList.remove('active')
 $('startScanner').disabled = !$('redeemButton') || $('redeemButton').disabled
 $('stopScanner').disabled = true
 $('scannerStatus').textContent = message
}

async function startScanner() {
 if(scannerRunning || redeeming) return
 $('startScanner').disabled = true
 $('scannerStatus').textContent = 'Memuat scanner kamera…'
 try {
  if(!window.isSecureContext) throw new Error('Kamera memerlukan HTTPS. Buka halaman Booth melalui alamat HTTPS.')
  const {BrowserQRCodeReader} = await import('https://cdn.jsdelivr.net/npm/@zxing/browser@0.1.5/+esm')
  scannerReader = new BrowserQRCodeReader()
  $('scannerFrame').classList.add('active')
  $('scannerStatus').textContent = 'Meminta izin kamera…'
  scannerControls = await scannerReader.decodeFromVideoDevice(undefined, 'qrVideo', async (result, error) => {
   if(result && !redeeming) {
    const text = result.getText()
    if(text) {
     await stopScanner('QR terbaca. Memvalidasi token…')
     $('tokenInput').value = text
     await redeemToken(text)
    }
   }
  })
  scannerRunning = true
  $('stopScanner').disabled = false
  $('scannerStatus').textContent = 'Kamera aktif. Arahkan kamera belakang ke QR pemain.'
 } catch(error) {
  await stopScanner('Kamera tidak dapat diaktifkan.')
  $('scannerStatus').textContent = (error?.message || 'Gagal membuka kamera.') + ' Periksa izin kamera browser atau gunakan input token manual.'
 }
}

async function redeemToken(token) {
 if(!token || redeeming) return
 redeeming = true
 const button=$('redeemButton');button.disabled=true;button.textContent='Memverifikasi…'
 $('startScanner').disabled=true
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
  $('scannerStatus').textContent='Check-in berhasil. Siap memindai pemain berikutnya.'
 }catch(error){
  result.className='booth-result error'
  result.innerHTML='<strong>Check-in gagal</strong><p></p><p class="booth-note">Pastikan token belum kedaluwarsa, belum digunakan, dan akun petugas merupakan anggota aktif venue sesi ini.</p>'
  result.querySelector('p').textContent=error.message||'Token tidak valid.'
 }finally{
  redeeming=false
  button.disabled=false;button.textContent='Verifikasi & check-in'
  $('startScanner').disabled=false
  $('tokenInput').focus()
 }
}

$('startScanner').addEventListener('click',startScanner)
$('stopScanner').addEventListener('click',()=>stopScanner())
$('redeemForm').addEventListener('submit',async e=>{
 e.preventDefault()
 await redeemToken($('tokenInput').value.trim())
})
supabase.auth.onAuthStateChange(()=>checkAuth().catch(e=>{$('boothAuth').textContent=e.message}))
checkAuth().catch(e=>{$('boothAuth').textContent='Gagal memeriksa login: '+e.message})

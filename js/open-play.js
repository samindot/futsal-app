import { supabase } from './supabase.js'
import { initAuthNav } from './nav-auth.js'

const $ = id => document.getElementById(id)
const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]))
const dateTime = (date, time, duration) => {
  if (!date) return 'Jadwal belum tersedia'
  const start = new Date(date + 'T' + String(time || '00:00').slice(0,5) + ':00')
  const end = new Date(start.getTime() + Number(duration || 0) * 3600000)
  return start.toLocaleString('id-ID',{weekday:'short',day:'numeric',month:'short',hour:'2-digit',minute:'2-digit'}) + ' – ' + end.toLocaleTimeString('id-ID',{hour:'2-digit',minute:'2-digit'})
}
initAuthNav()
let currentUser = null
let sessions = []
let bookings = []
let myParticipants = new Map()

async function loadAuth() {
  const {data,error}=await supabase.auth.getSession()
  if(error) throw error
  currentUser=data.session?.user || null
  $('authNotice').textContent=currentUser ? 'Login sebagai ' + (currentUser.user_metadata?.display_name || currentUser.email || 'pemain') + '. Booking hanya menampilkan milik akunmu yang sudah terkonfirmasi.' : 'Login diperlukan untuk membuat sesi, bergabung, dan membuat QR check-in.'
  $('createForm').querySelectorAll('input,select,textarea,button').forEach(el=>el.disabled=!currentUser)
  if(!currentUser) {
    $('bookingSelect').innerHTML='<option value="">Login untuk melihat booking</option>'
    $('sessionList').innerHTML='<div class="op-empty">Kamu bisa melihat sesi yang terbuka setelah login. <a href="./login.html?next=open-play.html">Login / daftar</a></div>'
    return
  }
  await Promise.all([loadBookings(),loadSessions()])
}
async function loadBookings() {
  const {data,error}=await supabase.from('bookings').select('id,booking_date,start_time,duration_hours,status,field_id,venue_id,fields(name,location)').eq('created_by',currentUser.id).eq('status','confirmed').order('booking_date',{ascending:true})
  if(error) {
    $('bookingSelect').innerHTML='<option value="">Gagal memuat booking</option>'
    $('createMessage').innerHTML='<div class="op-message error">'+esc(error.message)+'</div>'
    return
  }
  bookings=data||[]
  $('bookingSelect').innerHTML='<option value="">Pilih booking…</option>'+bookings.map(b=>'<option value="'+esc(b.id)+'">'+esc(b.fields?.name||'Lapangan')+' · '+esc(dateTime(b.booking_date,b.start_time,b.duration_hours))+'</option>').join('')
  if(!bookings.length) $('bookingSelect').innerHTML='<option value="">Belum ada booking terkonfirmasi</option>'
}
async function loadSessions() {
  $('sessionList').innerHTML='<div class="op-empty">Memuat sesi…</div>'
  const {data,error}=await supabase.from('open_play_sessions').select('id,venue_id,booking_id,host_id,title,max_players,skill_level,notes,status,created_at,bookings(booking_date,start_time,duration_hours,fields(name,location))').in('status',['open','full']).order('created_at',{ascending:false}).limit(50)
  if(error) {
    $('sessionList').innerHTML='<div class="op-message error">Tidak dapat memuat sesi: '+esc(error.message)+'</div>'
    return
  }
  sessions=data||[]
  myParticipants = new Map()
  if(currentUser && sessions.length) {
    const {data: ownRows, error: ownError} = await supabase.from('open_play_participants').select('session_id,status,attendance_status').eq('player_id',currentUser.id)
    if(!ownError) for(const row of (ownRows||[])) myParticipants.set(row.session_id,row)
  }
  if(!sessions.length){$('sessionList').innerHTML='<div class="op-empty">Belum ada sesi Open Play. Jika punya booking terkonfirmasi, kamu bisa membuka sesi pertama.</div>';return}
  $('sessionList').replaceChildren()
  for(const s of sessions){
    const card=document.createElement('article');card.className='op-card'
    const skill={any:'Semua level',beginner:'Pemula',intermediate:'Menengah',advanced:'Lanjutan'}[s.skill_level]||s.skill_level
    card.innerHTML='<h3>'+esc(s.title)+'</h3><div class="op-meta">'+esc(s.bookings?.fields?.name||'Lapangan')+' · '+esc(dateTime(s.bookings?.booking_date,s.bookings?.start_time,s.bookings?.duration_hours))+'</div><p class="op-meta">Kapasitas '+esc(s.max_players)+' pemain · '+esc(skill)+' · '+(s.status==='full'?'Penuh':'Terbuka')+'</p>'+(s.notes?'<p>'+esc(s.notes)+'</p>':'')
    const actions=document.createElement('div');actions.className='op-actions'
    if(currentUser){
      const participant=myParticipants.get(s.id)
      if(participant?.status==='joined') {
        const qr=document.createElement('button');qr.className='button button-accent';qr.textContent=participant.attendance_status==='checked_in'?'Sudah check-in':'Buat QR check-in';qr.disabled=participant.attendance_status==='checked_in';qr.addEventListener('click',()=>makeToken(s.id,card));actions.append(qr)
        if(participant.attendance_status!=='checked_in'){
          const leave=document.createElement('button');leave.className='button button-outline';leave.textContent='Batal ikut';leave.addEventListener('click',()=>leaveSession(s.id));actions.append(leave)
        }
      } else {
        const join=document.createElement('button');join.className='button button-accent';join.textContent='Gabung sesi';join.addEventListener('click',()=>joinSession(s.id));actions.append(join)
      }
    } else {
      const login=document.createElement('a');login.className='button button-accent';login.href='./login.html?next=open-play.html';login.textContent='Login untuk bergabung';actions.append(login)
    }
    card.append(actions);$('sessionList').append(card)
  }
}
async function joinSession(id) {
  $('sessionMessage').innerHTML=''
  try{
    const {data,error}=await supabase.rpc('join_open_play_session',{p_session_id:id})
    if(error) throw error
    $('sessionMessage').innerHTML='<div class="op-message">Respons server: '+esc(typeof data==='string'?data:JSON.stringify(data))+'</div>'
    await loadSessions()
  }catch(e){$('sessionMessage').innerHTML='<div class="op-message error">'+esc(e.message)+'</div>'}
}
async function leaveSession(id) {
  try {
    const {error}=await supabase.rpc('leave_open_play_session',{p_session_id:id})
    if(error) throw error
    $('sessionMessage').innerHTML='<div class="op-message">Kamu sudah keluar dari sesi.</div>'
    await loadSessions()
  } catch(e) {$('sessionMessage').innerHTML='<div class="op-message error">'+esc(e.message)+'</div>'}
}
async function makeToken(id,card) {
  try{
    const {data,error}=await supabase.rpc('create_open_play_checkin_token',{p_session_id:id})
    if(error) throw error
    const token=String(data)
    const box=document.createElement('div');box.className='op-message'
    box.innerHTML='<strong>Token check-in dibuat</strong><p>Token berlaku 2 menit. Tunjukkan QR ini langsung kepada petugas.</p><div class="qr-slot" style="background:white;padding:12px;display:inline-block;border-radius:8px"></div><p><code class="token-text"></code></p><button class="button button-outline copy-token" type="button">Salin token</button>'
    box.querySelector('.token-text').textContent=token
    card.append(box)
    const canvas=document.createElement('canvas');box.querySelector('.qr-slot').append(canvas)
    try {
      const {default:QRCode}=await import('https://cdn.jsdelivr.net/npm/qrcode@1.5.4/+esm')
      await QRCode.toCanvas(canvas,token,{width:210,margin:1})
    } catch { box.querySelector('.qr-slot').textContent='QR tidak dapat dirender. Gunakan token teks di bawah.' }
    box.querySelector('.copy-token').addEventListener('click',async()=>{try{await navigator.clipboard.writeText(token);box.querySelector('.copy-token').textContent='Tersalin'}catch{box.querySelector('.token-text').textContent=token}})
  }catch(e){$('sessionMessage').innerHTML='<div class="op-message error">'+esc(e.message)+'</div>'}
}
$('createForm').addEventListener('submit',async e=>{
  e.preventDefault()
  if(!currentUser){$('createMessage').innerHTML='<div class="op-message error">Login terlebih dahulu.</div>';return}
  const button=$('createButton');button.disabled=true;button.textContent='Membuat sesi…'
  try{
    const {data,error}=await supabase.rpc('create_open_play_session',{p_booking_id:$('bookingSelect').value,p_title:$('sessionTitle').value.trim(),p_max_players:Number($('maxPlayers').value),p_skill_level:$('skillLevel').value,p_notes:$('sessionNotes').value.trim()||null})
    if(error) throw error
    $('createMessage').innerHTML='<div class="op-message">Sesi Open Play berhasil dibuat. Host otomatis terdaftar sebagai peserta.</div>'
    $('sessionTitle').value='';$('sessionNotes').value=''
    await loadSessions()
  }catch(e){$('createMessage').innerHTML='<div class="op-message error">'+esc(e.message)+'</div>'}
  finally{button.disabled=false;button.textContent='Buat sesi Open Play'}
})
$('refreshButton').addEventListener('click',loadSessions)
supabase.auth.onAuthStateChange(()=>{loadAuth().catch(e=>{$('authNotice').textContent=e.message})})
loadAuth().catch(e=>{$('authNotice').textContent='Gagal memeriksa login: '+e.message})

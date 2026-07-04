// Preuve UI bug #2 : 3 clients dans la salle d'attente. L'hôte (A) se déconnecte ;
// le statut d'hôte migre vers B, qui doit VOIR apparaître les contrôles d'hôte à
// l'écran (bouton Paramètres + badge « Hote »), pas juste un changement serveur.
// Rouge sans le fix (B ne devient jamais hôte) -> vert avec le fix.
// Prérequis : stack émulateurs + build web ENABLE_SEMANTICS=true (voir DEV-EMULATORS.md).
import { chromium } from 'playwright';
import { openMultiplayerAuth, fillField, boxByText, tap, waitBox } from './flutter-semantics.mjs';
const URL='http://localhost:8081/', SERVER='http://localhost:3000';
const log=(...a)=>console.log(new Date().toISOString().slice(11,19),...a);
async function seed(){const id=Date.now().toString().slice(-7)+Math.floor(Math.random()*90);const email=`ho${id}@example.com`;const r=await fetch(`${SERVER}/api/auth/register-password`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({username:`ho${id}`,displayName:`HO${id}`,email,password:'MotDePasse123'})});if(r.status!==201)throw new Error('seed '+r.status);return email;}
function attach(p){p._ok=false;p.on('response',r=>{if(r.url().includes('/api/auth/login-password')&&r.status()===200)p._ok=true;});}
async function login(p,email,who){for(let a=1;a<=6&&!p._ok;a++){await p.goto(URL,{waitUntil:'load'});await p.waitForTimeout(9000);await openMultiplayerAuth(p);await fillField(p,"E-mail ou nom d'utilisateur",email);await fillField(p,'Mot de passe','MotDePasse123');await tap(p,await boxByText(p,/^SE CONNECTER$/));for(let i=0;i<8&&!p._ok;i++)await p.waitForTimeout(1000);}if(!p._ok)throw new Error(who+' login KO');await p.waitForTimeout(2500);log(who+' connecté');}
async function join(p,code){await tap(p,await waitBox(p,()=>boxByText(p,/Rejoindre un salon/)));await p.waitForTimeout(2500);const priv=await boxByText(p,/Salon Privé|privé/i);if(priv){await tap(p,priv);await p.waitForTimeout(2500);}const inp=await p.evaluate(()=>{const e=document.querySelector('input');if(!e)return null;const r=e.getBoundingClientRect();return{x:r.x+r.width/2,y:r.y+r.height/2};});await p.mouse.click(inp.x,inp.y);await p.waitForTimeout(500);await p.keyboard.insertText(code);await p.waitForTimeout(500);await tap(p,await boxByText(p,/REJOINDRE/i));await p.waitForTimeout(3500);}
const hasHostCtrl=(p)=>p.evaluate(()=>[...document.querySelectorAll('[role="button"]')].some(e=>/Paramètres/i.test((e.textContent||'').trim())));
const isHost=(p)=>p.evaluate(()=>[...document.querySelectorAll('flt-semantics')].filter(e=>{const t=(e.textContent||'').trim();return t.includes('Vous')&&t.length<40;}).some(e=>(e.textContent||'').includes('Hote')));
const nudge=async p=>{await p.mouse.move(700,400);await p.mouse.move(701,401);};

(async()=>{
  const [eA,eB,eC]=[await seed(),await seed(),await seed()];
  const br=await chromium.launch({headless:true});
  const ctxA=await br.newContext({viewport:{width:1400,height:900}});
  const A=await ctxA.newPage();
  const B=await(await br.newContext({viewport:{width:1400,height:900}})).newPage();
  const C=await(await br.newContext({viewport:{width:1400,height:900}})).newPage();
  attach(A);attach(B);attach(C);
  await login(A,eA,'A');
  await tap(A,await waitBox(A,()=>boxByText(A,/Créer un salon/)));await A.waitForTimeout(2000);
  await tap(A,await waitBox(A,()=>boxByText(A,/Salon Privé/)));await A.waitForTimeout(2000);
  await tap(A,await waitBox(A,()=>boxByText(A,/CRÉER LE SALON/)));await A.waitForTimeout(4000);
  const code=await A.evaluate(()=>{for(const e of document.querySelectorAll('flt-semantics')){const t=(e.textContent||'').trim();if(/^[A-Z0-9]{8}$/.test(t))return t;}return null;});
  log('code',code);
  await login(B,eB,'B');await join(B,code);
  await login(C,eC,'C');await join(C,code);
  await B.waitForTimeout(1500);await nudge(B);
  const bCtrlBefore=await hasHostCtrl(B); const bHostBefore=await isHost(B);
  log('AVANT départ hôte — B contrôles hôte(Paramètres):',bCtrlBefore,' badge Hote:',bHostBefore,'(attendu false, A est hôte)');
  await B.screenshot({path:'/tmp/host-B-before.png'});
  log('>>> l\'hôte A quitte le salon (déconnexion)');
  await ctxA.close();
  let bCtrlAfter=false,bHostAfter=false;
  for(let i=0;i<20;i++){await B.waitForTimeout(1200);await nudge(B);bCtrlAfter=await hasHostCtrl(B);bHostAfter=await isHost(B);if(bCtrlAfter&&bHostAfter)break;}
  log('APRÈS départ hôte — B contrôles hôte(Paramètres):',bCtrlAfter,' badge Hote:',bHostAfter);
  await B.screenshot({path:'/tmp/host-B-after.png'});
  const ok = !bCtrlBefore && bCtrlAfter && bHostAfter;
  console.log(ok?'\n✅ PREUVE UI bug#2 : après le départ de l\'hôte, B devient hôte (badge Hote) et VOIT apparaître les contrôles (Paramètres)':'\n❌ B ne devient pas hôte / pas de contrôles (bug reproduit)');
  await br.close();process.exit(ok?0:1);
})().catch(e=>{console.error('❌',e.message);process.exit(1);});

// Preuve UI bug #1 : 3 vrais clients en partie. B se déconnecte ; son statut de
// présence passe de « En ligne » à « Hors ligne » sur l'écran de A (lu via le label
// Semantics de la pastille, pas une couleur de pixel), la partie continuant grâce à C.
// Prérequis : stack émulateurs + build web ENABLE_SEMANTICS=true (voir DEV-EMULATORS.md).
import { chromium } from 'playwright';
import { openMultiplayerAuth, fillField, boxByText, tap, waitBox } from './flutter-semantics.mjs';
const URL='http://localhost:8081/', SERVER='http://localhost:3000';
const log=(...a)=>console.log(new Date().toISOString().slice(11,19),...a);
async function seed(){const id=Date.now().toString().slice(-7)+Math.floor(Math.random()*90);const email=`p3${id}@example.com`;const r=await fetch(`${SERVER}/api/auth/register-password`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({username:`p3${id}`,displayName:`P3${id}`,email,password:'MotDePasse123'})});if(r.status!==201)throw new Error('seed '+r.status);return email;}
function attach(p){p._ok=false;p.on('response',r=>{if(r.url().includes('/api/auth/login-password')&&r.status()===200)p._ok=true;});}
async function login(p,email,who){for(let a=1;a<=6&&!p._ok;a++){await p.goto(URL,{waitUntil:'load'});await p.waitForTimeout(9000);await openMultiplayerAuth(p);await fillField(p,"E-mail ou nom d'utilisateur",email);await fillField(p,'Mot de passe','MotDePasse123');await tap(p,await boxByText(p,/^SE CONNECTER$/));for(let i=0;i<8&&!p._ok;i++)await p.waitForTimeout(1000);}if(!p._ok)throw new Error(who+' login KO');await p.waitForTimeout(2500);log(who+' connecté');}
async function join(p,code){await tap(p,await waitBox(p,()=>boxByText(p,/Rejoindre un salon/)));await p.waitForTimeout(2500);const priv=await boxByText(p,/Salon Privé|privé/i);if(priv){await tap(p,priv);await p.waitForTimeout(2500);}const inp=await p.evaluate(()=>{const e=document.querySelector('input');if(!e)return null;const r=e.getBoundingClientRect();return{x:r.x+r.width/2,y:r.y+r.height/2};});await p.mouse.click(inp.x,inp.y);await p.waitForTimeout(500);await p.keyboard.insertText(code);await p.waitForTimeout(500);await tap(p,await boxByText(p,/REJOINDRE/i));await p.waitForTimeout(3500);}
async function memo(p){for(let i=0;i<25;i++){if(await boxByText(p,/^Carte à mémoriser 1$/))break;await p.waitForTimeout(600);}const c1=await boxByText(p,/^Carte à mémoriser 1$/);if(c1)await tap(p,c1);await p.waitForTimeout(400);const c2=await boxByText(p,/^Carte à mémoriser 2$/);if(c2)await tap(p,c2);await p.waitForTimeout(400);const ch=await boxByText(p,/CHOISIS 2 CARTES/i);if(ch)await tap(p,ch);}
const countOff=(p)=>p.evaluate(()=>[...document.querySelectorAll('flt-semantics')].filter(e=>(e.textContent||'').trim()==='Hors ligne').length);
const countOn=(p)=>p.evaluate(()=>[...document.querySelectorAll('flt-semantics')].filter(e=>(e.textContent||'').trim()==='En ligne').length);
const nudge=async p=>{await p.mouse.move(700,400);await p.mouse.move(701,401);};

(async()=>{
  const [eA,eB,eC]=[await seed(),await seed(),await seed()];
  const br=await chromium.launch({headless:true});
  const ctxB=await br.newContext({viewport:{width:1400,height:900}});
  const A=await(await br.newContext({viewport:{width:1400,height:900}})).newPage();
  const B=await ctxB.newPage();
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
  for(const [p] of [[C],[B],[A]]){const r=await boxByText(p,/Passer pret/i);if(r){await tap(p,r);await p.waitForTimeout(1000);}}
  await A.waitForTimeout(1500);
  await tap(A,await boxByText(A,/Lancer/i));await A.waitForTimeout(1800);
  const cf=await boxByText(A,/^Lancer$/i);if(cf)await tap(A,cf);await A.waitForTimeout(9000);
  await memo(A);await memo(B);await memo(C);
  let onBefore=0;
  for(let i=0;i<40;i++){await A.waitForTimeout(1000);await nudge(A);onBefore=await countOn(A);if(onBefore>0)break;}
  const offBefore=await countOff(A);
  log(`AVANT — En ligne=${onBefore} Hors ligne=${offBefore}`);
  log('>>> déconnexion de B');
  await ctxB.close();
  let offAfter=0;
  for(let i=0;i<25;i++){await A.waitForTimeout(1200);await nudge(A);offAfter=await countOff(A);if(offAfter>offBefore)break;}
  log(`APRÈS — Hors ligne=${offAfter}`);
  await A.screenshot({path:'/tmp/presence3-A.png'});
  const ok=offBefore===0 && offAfter>=1;
  console.log(ok?'\n✅ PREUVE UI bug#1 : après déconnexion de B, son statut passe « Hors ligne » sur l\'écran de A (jeu toujours en cours grâce à C)':'\n❌ label non passé à Hors ligne');
  await br.close();process.exit(ok?0:1);
})().catch(e=>{console.error('❌',e.message);process.exit(1);});

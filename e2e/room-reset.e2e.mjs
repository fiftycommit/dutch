// Preuve UI bug #3 : 3 vrais clients. A+B jouent jusqu'aux résultats (A crie DUTCH),
// A revient au salon et B DÉCROCHE sur les résultats, puis C rejoint le MÊME salon.
// Discriminateur VALIDE (le client masque le statut) : une NOUVELLE partie doit
// pouvoir démarrer. Sans le fix, le salon reste coincé en 'ended' (pas de bouton
// prêt/lancer, aucune partie ne redémarre). Prérequis : stack émulateurs + build web
// ENABLE_SEMANTICS=true (voir DEV-EMULATORS.md).
import { chromium } from 'playwright';
import { openMultiplayerAuth, fillField, boxByText, tap, waitBox } from './flutter-semantics.mjs';
const URL='http://localhost:8081/', SERVER='http://localhost:3000';
const log=(...a)=>console.log(new Date().toISOString().slice(11,19),...a);
async function seed(){const id=Date.now().toString().slice(-7)+Math.floor(Math.random()*90);const email=`b3${id}@example.com`;const r=await fetch(`${SERVER}/api/auth/register-password`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({username:`b3${id}`,displayName:`B3${id}`,email,password:'MotDePasse123'})});if(r.status!==201)throw new Error('seed '+r.status);return email;}
function attach(p){p._ok=false;p.on('response',r=>{if(r.url().includes('/api/auth/login-password')&&r.status()===200)p._ok=true;});}
async function login(p,email,who){for(let a=1;a<=6&&!p._ok;a++){await p.goto(URL,{waitUntil:'load'});await p.waitForTimeout(9000);await openMultiplayerAuth(p);await fillField(p,"E-mail ou nom d'utilisateur",email);await fillField(p,'Mot de passe','MotDePasse123');await tap(p,await boxByText(p,/^SE CONNECTER$/));for(let i=0;i<8&&!p._ok;i++)await p.waitForTimeout(1000);}if(!p._ok)throw new Error(who+' login KO');await p.waitForTimeout(2500);log(who+' connecté');}
async function join(p,code){await tap(p,await waitBox(p,()=>boxByText(p,/Rejoindre un salon/)));await p.waitForTimeout(2500);const priv=await boxByText(p,/Salon Privé|privé/i);if(priv){await tap(p,priv);await p.waitForTimeout(2500);}const inp=await p.evaluate(()=>{const e=document.querySelector('input');if(!e)return null;const r=e.getBoundingClientRect();return{x:r.x+r.width/2,y:r.y+r.height/2};});await p.mouse.click(inp.x,inp.y);await p.waitForTimeout(500);await p.keyboard.insertText(code);await p.waitForTimeout(500);await tap(p,await boxByText(p,/REJOINDRE/i));await p.waitForTimeout(3500);}
async function memo(p){for(let i=0;i<25;i++){if(await boxByText(p,/^Carte à mémoriser 1$/))break;await p.waitForTimeout(600);}const c1=await boxByText(p,/^Carte à mémoriser 1$/);if(c1)await tap(p,c1);await p.waitForTimeout(400);const c2=await boxByText(p,/^Carte à mémoriser 2$/);if(c2)await tap(p,c2);await p.waitForTimeout(400);const ch=await boxByText(p,/CHOISIS 2 CARTES/i);if(ch)await tap(p,ch);}
const has=(p,re,en=false)=>p.evaluate(({s,e})=>{const rx=new RegExp(s,'i');const els=[...document.querySelectorAll('[role="button"]')].filter(x=>rx.test((x.textContent||'').trim())&&x.getBoundingClientRect().width>0&&x.getBoundingClientRect().y>=0);if(!els.length)return false;if(!e)return true;return els.some(x=>x.getAttribute('aria-disabled')!=='true');},{s:re.source,e:en});
const tapT=async(p,re)=>{const b=await boxByText(p,re);if(b)await tap(p,b);return !!b;};
const hasResults=(p)=>p.evaluate(()=>[...document.querySelectorAll('flt-semantics')].some(e=>/RÉSULTATS|Retour au Salon/i.test((e.textContent||''))));
const texts=(p)=>p.evaluate(()=>[...new Set([...document.querySelectorAll('flt-semantics')].map(e=>(e.textContent||'').trim()).filter(t=>t&&t.length<26))].slice(0,30));

(async()=>{
  const [eA,eB,eC]=[await seed(),await seed(),await seed()];
  const br=await chromium.launch({headless:true});
  const ctxA=await br.newContext({viewport:{width:1400,height:900}});
  const ctxB=await br.newContext({viewport:{width:1400,height:900}});
  const A=await ctxA.newPage(), B=await ctxB.newPage();
  const C=await(await br.newContext({viewport:{width:1400,height:900}})).newPage();
  attach(A);attach(B);attach(C);
  await login(A,eA,'A');
  await tap(A,await waitBox(A,()=>boxByText(A,/Créer un salon/)));await A.waitForTimeout(2000);
  await tap(A,await waitBox(A,()=>boxByText(A,/Salon Privé/)));await A.waitForTimeout(2000);
  await tap(A,await waitBox(A,()=>boxByText(A,/CRÉER LE SALON/)));await A.waitForTimeout(4000);
  const code=await A.evaluate(()=>{for(const e of document.querySelectorAll('flt-semantics')){const t=(e.textContent||'').trim();if(/^[A-Z0-9]{8}$/.test(t))return t;}return null;});
  log('code',code);
  await login(B,eB,'B');await join(B,code);
  for(const [p] of [[B],[A]]){const r=await boxByText(p,/Passer pret/i);if(r){await tap(p,r);await p.waitForTimeout(1000);}}
  await A.waitForTimeout(1200);
  await tap(A,await boxByText(A,/Lancer/i));await A.waitForTimeout(1800);
  const cf=await boxByText(A,/^Lancer$/i);if(cf)await tap(A,cf);await A.waitForTimeout(9000);
  await memo(A);await memo(B);await A.waitForTimeout(4000);
  // jouer jusqu'aux résultats : appeler DUTCH puis dérouler les tours
  let dutch=false;
  for(let it=0;it<40;it++){
    if(await hasResults(A) && await hasResults(B)){log('RÉSULTATS atteints');break;}
    let acted=false;
    for(const [p,w] of [[A,'A'],[B,'B']]){
      if(!dutch && await has(p,/DUTCH/,true)){await tapT(p,/DUTCH/);await p.waitForTimeout(1300);await tapT(p,/DUTCH !/);dutch=true;acted=true;log(w+' appelle DUTCH (confirmé)');await p.waitForTimeout(2500);break;}
      if(await has(p,/PIOCHER/,true)){await tapT(p,/PIOCHER/);await p.waitForTimeout(1500);await tapT(p,/JETER/);acted=true;log(w+' pioche+jette');await p.waitForTimeout(2000);break;}
    }
    if(!acted)await A.waitForTimeout(1500);
  }
  const aRes=await hasResults(A);
  log('A sur résultats:',aRes);
  if(!aRes){log('⚠️ partie non terminée — impossible de tester le scénario');await A.screenshot({path:'/tmp/bug3-noend.png'});await br.close();process.exit(2);}
  // L'hôte et l'autre joueur QUITTENT depuis les résultats (déconnexion)
  log('>>> A (hôte) quitte proprement (Retour au Salon), B DÉCROCHE sur les résultats');
  await tapT(A,/Retour au Salon/); await A.waitForTimeout(2500);
  await ctxB.close(); await new Promise(r=>setTimeout(r,3000));
  // Un 3e client rejoint le MÊME salon
  await login(C,eC,'C');await join(C,code);
  await C.waitForTimeout(2500);
  // Discriminateur VALIDE et visible : sur un salon coincé en 'ended', on ne peut
  // PAS relancer une partie. A (hôte, revenu au salon) + C passent prêts, A lance,
  // et on vérifie qu'une NOUVELLE partie démarre (écran mémorisation).
  for(const [p,w] of [[C,'C'],[A,'A']]){const r=await boxByText(p,/Passer pret/i);if(r){await tap(p,r);log(w+' prêt');await p.waitForTimeout(1200);}else log(w+' pas de bouton prêt');}
  await A.waitForTimeout(1500);
  const lancer=await boxByText(A,/Lancer/i);
  if(lancer){await tap(A,lancer);await A.waitForTimeout(1500);const cf2=await boxByText(A,/^Lancer$/i);if(cf2)await tap(A,cf2);log('A tente de lancer');}else log('A: pas de bouton Lancer');
  await A.waitForTimeout(9000);
  // nouvelle partie démarrée ? (mémorisation visible sur A ou C)
  let started=false;
  for(let i=0;i<12;i++){if(await boxByText(A,/^Carte à mémoriser 1$/)||await boxByText(C,/^Carte à mémoriser 1$/)||await boxByText(A,/CHOISIS 2 CARTES/i)){started=true;break;}await A.waitForTimeout(1000);}
  log('nouvelle partie démarrée:',started);
  await A.screenshot({path:'/tmp/bug3-newgame.png'});
  const ok = started;
  console.log(ok?'\n✅ PREUVE UI bug#3 : salon revenu en salle d\'attente FONCTIONNELLE — une nouvelle partie démarre après le départ des joueurs des résultats':'\n❌ impossible de relancer une partie (salon coincé en ended — bug reproduit)');
  await br.close();process.exit(ok?0:1);
})().catch(e=>{console.error('❌',e.message);process.exit(1);});

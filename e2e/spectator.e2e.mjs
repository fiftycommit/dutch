// Preuve UI bug #4 : 3 clients pré-connectés. A+B jouent (partie active), puis C
// rejoint et clique REGARDER LA PARTIE. C doit voir la TABLE DE JEU en direct
// (joueurs, tour courant, vraie défausse, deck) via un vrai contenu — pas le
// placeholder 'La partie va commencer...' — et ne peut RIEN faire (Mode Spectateur).
// NB : pré-login des 3 pour un join rapide (sinon les joueurs idle se font AFK-kick).
// Prérequis : stack émulateurs + build web ENABLE_SEMANTICS=true (voir DEV-EMULATORS.md).
import { chromium } from 'playwright';
import { openMultiplayerAuth, fillField, boxByText, tap, waitBox } from './flutter-semantics.mjs';
const URL='http://localhost:8081/', SERVER='http://localhost:3000';
const log=(...a)=>console.log(new Date().toISOString().slice(11,19),...a);
async function seed(){const id=Date.now().toString().slice(-7)+Math.floor(Math.random()*90);const email=`sp${id}@example.com`;const r=await fetch(`${SERVER}/api/auth/register-password`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({username:`sp${id}`,displayName:`SP${id}`,email,password:'MotDePasse123'})});if(r.status!==201)throw new Error('seed '+r.status);return email;}
function attach(p){p._ok=false;p.on('response',r=>{if(r.url().includes('/api/auth/login-password')&&r.status()===200)p._ok=true;});}
async function login(p,email,who){for(let a=1;a<=6&&!p._ok;a++){await p.goto(URL,{waitUntil:'load'});await p.waitForTimeout(9000);await openMultiplayerAuth(p);await fillField(p,"E-mail ou nom d'utilisateur",email);await fillField(p,'Mot de passe','MotDePasse123');await tap(p,await boxByText(p,/^SE CONNECTER$/));for(let i=0;i<8&&!p._ok;i++)await p.waitForTimeout(1000);}if(!p._ok)throw new Error(who+' login KO');await p.waitForTimeout(2500);log(who+' connecté');}
async function join(p,code){await tap(p,await waitBox(p,()=>boxByText(p,/Rejoindre un salon/)));await p.waitForTimeout(2500);const priv=await boxByText(p,/Salon Privé|privé/i);if(priv){await tap(p,priv);await p.waitForTimeout(2500);}const inp=await p.evaluate(()=>{const e=document.querySelector('input');if(!e)return null;const r=e.getBoundingClientRect();return{x:r.x+r.width/2,y:r.y+r.height/2};});await p.mouse.click(inp.x,inp.y);await p.waitForTimeout(500);await p.keyboard.insertText(code);await p.waitForTimeout(500);await tap(p,await boxByText(p,/REJOINDRE/i));await p.waitForTimeout(3500);}
async function memo(p){for(let i=0;i<25;i++){if(await boxByText(p,/^Carte à mémoriser 1$/))break;await p.waitForTimeout(600);}const c1=await boxByText(p,/^Carte à mémoriser 1$/);if(c1)await tap(p,c1);await p.waitForTimeout(400);const c2=await boxByText(p,/^Carte à mémoriser 2$/);if(c2)await tap(p,c2);await p.waitForTimeout(400);const ch=await boxByText(p,/CHOISIS 2 CARTES/i);if(ch)await tap(p,ch);}
const has=(p,re,en=false)=>p.evaluate(({s,e})=>{const rx=new RegExp(s,'i');const els=[...document.querySelectorAll('[role="button"]')].filter(x=>rx.test((x.textContent||'').trim())&&x.getBoundingClientRect().width>0&&x.getBoundingClientRect().y>=0);if(!els.length)return false;if(!e)return true;return els.some(x=>x.getAttribute('aria-disabled')!=='true');},{s:re.source,e:en});
const tapT=async(p,re)=>{const b=await boxByText(p,re);if(b)await tap(p,b);return !!b;};
const texts=(p)=>p.evaluate(()=>[...new Set([...document.querySelectorAll('flt-semantics')].map(e=>(e.textContent||'').trim()).filter(t=>t&&t.length<28))].slice(0,40));
const nudge=async p=>{await p.mouse.move(700,400);await p.mouse.move(701,401);};

(async()=>{
  const [eA,eB,eC]=[await seed(),await seed(),await seed()];
  const br=await chromium.launch({headless:true});
  const A=await(await br.newContext({viewport:{width:1400,height:900}})).newPage();
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
  await login(C,eC,'C'); // C pré-connecté pendant la salle d'attente (pas d'AFK), join rapide ensuite
  for(const [p] of [[B],[A]]){const r=await boxByText(p,/Passer pret/i);if(r){await tap(p,r);await p.waitForTimeout(1000);}}
  await A.waitForTimeout(1200);await tap(A,await boxByText(A,/Lancer/i));await A.waitForTimeout(1800);
  const cf=await boxByText(A,/^Lancer$/i);if(cf)await tap(A,cf);await A.waitForTimeout(9000);
  await memo(A);await memo(B);await A.waitForTimeout(5000);
  // jouer 2 tours (pas de DUTCH) pour être clairement en partie active
  for(let t=0;t<2;t++){for(const [p,w] of [[A,'A'],[B,'B']]){if(await has(p,/PIOCHER/,true)){await tapT(p,/PIOCHER/);await p.waitForTimeout(1500);await tapT(p,/JETER/);log(w+' joue');await p.waitForTimeout(2500);break;}}}
  // état de A juste avant le join de C
  await nudge(A);const aTexts=await texts(A);
  log('=== ÉTAT A (joueur) ===');log(JSON.stringify(aTexts));
  // C REJOINT EN PLEINE PARTIE
  log('>>> C rejoint en pleine partie');
  await join(C,code);
  await C.waitForTimeout(5000);await nudge(C);await C.waitForTimeout(1500);
  // C clique REGARDER LA PARTIE pour entrer dans la vue spectateur du jeu
  const regarder=await boxByText(C,/REGARDER LA PARTIE/i);
  log('bouton REGARDER LA PARTIE présent:',!!regarder);
  if(regarder){await tap(C,regarder);await C.waitForTimeout(6000);}
  await nudge(C);await C.waitForTimeout(2000);await nudge(C);
  const cTexts=await texts(C);
  const cCanDraw=await has(C,/PIOCHER/,true);
  const cHasTable=await C.evaluate(()=>[...document.querySelectorAll('flt-semantics')].some(e=>/Pioche|Défausse|Carte \d+ de/i.test(e.textContent||'')));
  log('=== VUE SPECTATEUR C ===');log(JSON.stringify(cTexts));
  log('C peut piocher (ne devrait PAS):',cCanDraw,' | table de jeu visible:',cHasTable);
  await C.screenshot({path:'/tmp/spec-C-watch.png'});await A.screenshot({path:'/tmp/spec-A.png'});
  // SYNC : A/B jouent une action, C doit se mettre à jour
  log('>>> action de jeu pendant que C regarde');
  let played=false;
  for(const [p,w] of [[A,'A'],[B,'B']]){if(await has(p,/PIOCHER/,true)){await tapT(p,/PIOCHER/);await p.waitForTimeout(1500);await tapT(p,/JETER/);played=true;log(w+' joue (défausse)');await p.waitForTimeout(3000);break;}}
  await nudge(C);await C.waitForTimeout(2000);
  const cHasTableAfter=await C.evaluate(()=>[...document.querySelectorAll('flt-semantics')].some(e=>/Pioche|Défausse|Carte \d+ de/i.test(e.textContent||'')));
  const cPlaceholder=await C.evaluate(()=>[...document.querySelectorAll('flt-semantics')].some(e=>/La partie va commencer|VOUS ÊTES SPECTATEUR/i.test(e.textContent||'')));
  await C.screenshot({path:'/tmp/spec-C-after.png'});
  log('=== VERDICT SPECTATEUR ===');
  log('table de jeu visible pour C:',cHasTable||cHasTableAfter,' | placeholder « va commencer »:',cPlaceholder,' | C peut agir:',cCanDraw);
  const ok=(cHasTable||cHasTableAfter) && !cPlaceholder && !cCanDraw;
  console.log(ok?'\n✅ PREUVE UI bug#4 : le spectateur voit la TABLE DE JEU en direct (pas le placeholder), sans pouvoir agir':'\n❌ spectateur bloqué sur un placeholder / pas de table (bug reproduit)');
  await br.close();process.exit(ok?0:1);
})().catch(e=>{console.error('❌',e.message);process.exit(1);});

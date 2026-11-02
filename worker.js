/**
 * Affût — relais d'identification par photo
 *
 * Deux moteurs derrière une seule adresse :
 *   POST /            → Claude, pour la faune et les champignons
 *   POST /plantnet    → Pl@ntNet, pour la flore et les arbres
 *
 * Les clés restent sur Cloudflare : l'application ne les voit jamais.
 *
 * MISE EN PLACE, depuis le tableau de bord, sans ligne de commande :
 *   1. dash.cloudflare.com > Compute > Workers & Pages > votre relais
 *   2. Edit code : tout sélectionner, supprimer, coller ce fichier
 *   3. ligne ORIGINES ci-dessous : mettre l'adresse EXACTE de votre site
 *   4. Deploy
 *   5. Settings > Variables and Secrets > Add
 *        Secret  ANTHROPIC_API_KEY   votre clé sk-ant-...
 *        Secret  PLANTNET_API_KEY    votre clé Pl@ntNet
 *      puis Deploy
 *
 * La clé Pl@ntNet s'obtient sur my.plantnet.org — compte gratuit,
 * 500 identifications par jour.
 */

// >>> À MODIFIER : l'adresse exacte de votre site, sans barre oblique finale.
const ORIGINES = [
  'https://territoire1.pages.dev',
];

const entetes = (origine) => ({
  'Access-Control-Allow-Origin': origine || ORIGINES[0],
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
  'Access-Control-Max-Age': '86400',
});

function refus(message, code, origine) {
  return new Response(JSON.stringify({ erreur: message }), {
    status: code,
    headers: { 'Content-Type': 'application/json', ...entetes(origine) },
  });
}

export default {
  async fetch(request, env) {
    const origine = request.headers.get('Origin');
    const permise = ORIGINES.includes(origine);

    if (request.method === 'OPTIONS') {
      return new Response(null, { headers: entetes(permise ? origine : null) });
    }
    if (!permise) {
      return refus("Le relais refuse cette origine. Vérifiez la liste ORIGINES.", 403, null);
    }
    if (request.method !== 'POST') {
      return refus('Méthode non autorisée.', 405, origine);
    }

    const url = new URL(request.url);
    const versPlantnet = url.pathname.replace(/\/+$/, '').endsWith('/plantnet');

    let corps;
    try { corps = await request.json(); }
    catch (e) { return refus('Requête illisible.', 400, origine); }

    return versPlantnet
      ? plantnet(corps, env, origine)
      : claude(corps, env, origine);
  },
};

/* ------------------------------------------------------------------ */
/*  Pl@ntNet — flore et arbres                                        */
/*  Modèle spécialisé, entraîné sur des millions d'observations        */
/*  botaniques. Nettement supérieur à un modèle généraliste sur une    */
/*  feuille ou une écorce.                                            */
/* ------------------------------------------------------------------ */
async function plantnet(corps, env, origine) {
  if (!env.PLANTNET_API_KEY) {
    return refus("Clé Pl@ntNet absente du relais (secret PLANTNET_API_KEY).", 500, origine);
  }
  const images = Array.isArray(corps.images) ? corps.images.slice(0, 5) : [];
  if (!images.length) return refus('Aucune image reçue.', 400, origine);

  // Pl@ntNet attend un envoi multipart, pas du JSON.
  const form = new FormData();
  for (const im of images) {
    const b64 = String(im.b64 || '').replace(/^data:[^,]+,/, '');
    let octets;
    try {
      const bin = atob(b64);
      octets = new Uint8Array(bin.length);
      for (let i = 0; i < bin.length; i++) octets[i] = bin.charCodeAt(i);
    } catch (e) { return refus('Image illisible.', 400, origine); }
    form.append('images', new Blob([octets], { type: 'image/jpeg' }), 'photo.jpg');
    // organe : leaf, bark, flower, fruit, habit, ou auto
    form.append('organs', im.organe || 'auto');
  }

  const projet = corps.projet || 'all';
  const adresse = 'https://my-api.plantnet.org/v2/identify/' + projet +
    '?api-key=' + env.PLANTNET_API_KEY + '&lang=fr&nb-results=5';

  let r;
  try { r = await fetch(adresse, { method: 'POST', body: form }); }
  catch (e) { return refus('Pl@ntNet injoignable.', 502, origine); }

  const texte = await r.text();
  if (!r.ok) {
    // 404 = aucune espèce reconnue ; 429 = quota du jour épuisé
    const msg = r.status === 404 ? "Aucune espèce reconnue sur cette photo."
              : r.status === 429 ? "Quota Pl@ntNet épuisé pour aujourd'hui."
              : 'Pl@ntNet a refusé la requête (' + r.status + ').';
    return refus(msg, r.status, origine);
  }
  return new Response(texte, {
    headers: { 'Content-Type': 'application/json', ...entetes(origine) },
  });
}

/* ------------------------------------------------------------------ */
/*  Claude — faune et champignons                                     */
/*                                                                    */
/*  Plusieurs images sont acceptées : un champignon se lit sur trois  */
/*  plans (en place, dessous, base du pied) et une seule vue ne       */
/*  permet pas d'écarter un sosie.                                    */
/*                                                                    */
/*  Le relais ouvre lui-même l'enveloppe du modèle et renvoie le      */
/*  JSON utile. L'application attend {"candidats":[...]} : lui        */
/*  transmettre {"content":[...]} l'obligeait à défaire l'emballage   */
/*  deux fois, une fois par chemin d'appel.                           */
/* ------------------------------------------------------------------ */
async function claude(corps, env, origine) {
  if (!env.ANTHROPIC_API_KEY) {
    return refus('Clé Anthropic absente du relais.', 500, origine);
  }

  // image unique (faune, ancien format) ou liste de vues (champignons)
  const vues = Array.isArray(corps.images) && corps.images.length
    ? corps.images.slice(0, 4)
    : (corps.image ? [corps.image] : []);
  if (!vues.length) return refus('Aucune image reçue.', 400, origine);

  const invite = corps.invite || (
    "Tu identifies un animal sur une photo prise en France.\n" +
    (corps.especes ? corps.especes.join('\n') + '\n\n' : '') +
    'Réponds uniquement en JSON : {"candidats":[{"code":"...","confiance":0.8,"indices":"..."}]}'
  );

  const contenu = vues.map((v) => ({
    type: 'image',
    source: {
      type: 'base64',
      media_type: corps.media_type || 'image/jpeg',
      data: String(v).replace(/^data:[^,]+,/, ''),
    },
  }));
  contenu.push({ type: 'text', text: invite });

  let r;
  try {
    r = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': env.ANTHROPIC_API_KEY,
        'anthropic-version': '2023-06-01',
      },
      body: JSON.stringify({
        model: 'claude-sonnet-4-6',
        max_tokens: 1000,
        messages: [{ role: 'user', content: contenu }],
      }),
    });
  } catch (e) { return refus('Service injoignable.', 502, origine); }

  const texte = await r.text();
  if (!r.ok) return refus('Le modèle a refusé la requête (' + r.status + ').', r.status, origine);

  // On déballe la réponse ici. Si le format change, on renvoie le brut :
  // l'application sait lire les deux.
  try {
    const d = JSON.parse(texte);
    const brut = (d.content || [])
      .filter((x) => x.type === 'text')
      .map((x) => x.text)
      .join('')
      .trim()
      .replace(/^```(json)?/, '')
      .replace(/```$/, '')
      .trim();
    const utile = JSON.parse(brut);
    return new Response(JSON.stringify(utile), {
      headers: { 'Content-Type': 'application/json', ...entetes(origine) },
    });
  } catch (e) {
    return new Response(texte, {
      headers: { 'Content-Type': 'application/json', ...entetes(origine) },
    });
  }
}
